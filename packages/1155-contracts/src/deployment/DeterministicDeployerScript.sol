// spdx-license-identifier: mit
pragma solidity >=0.8.17;

import "forge-std/Script.sol";
import {Deployment, ChainConfig} from "./DeploymentConfig.sol";
import {ProxyShim} from "../utils/ProxyShim.sol";
import {DeterministicProxyDeployer} from "./DeterministicProxyDeployer.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {UpgradeGate} from "../upgrades/UpgradeGate.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ZoraDeployerUtils} from "./ZoraDeployerUtils.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";

struct DeterministicParams {
    bytes proxyDeployerCreationCode;
    bytes proxyCreationCode;
    address deployerAddress;
    address proxyDeployerAddress;
    bytes32 proxyDeployerSalt;
    bytes32 proxyShimSalt;
    bytes32 proxySalt;
    address deterministicProxyAddress;
}

contract DeterministicDeployerScript is Script {
    using stdJson for string;

    // copied from: https://github.com/karmacoma-eth/foundry-playground/blob/main/script/MineSaltScript.sol#L17C1-L36C9
    function mineSalt(address deployer, bytes32 initCodeHash, string memory startsWith) internal returns (bytes32 salt, address expectedAddress) {
        string[] memory args = new string[](8);
        args[0] = "cast";
        args[1] = "create2";
        args[2] = "--starts-with";
        args[3] = startsWith;
        args[4] = "--deployer";
        args[5] = LibString.toHexString(deployer);
        args[6] = "--init-code-hash";
        args[7] = LibString.toHexStringNoPrefix(uint256(initCodeHash), 32);
        string memory result = string(vm.ffi(args));

        uint256 addressIndex = LibString.indexOf(result, "Address: ");
        string memory addressStr = LibString.slice(result, addressIndex + 9, addressIndex + 9 + 42);
        expectedAddress = vm.parseAddress(addressStr);

        uint256 saltIndex = LibString.indexOf(result, "Salt: ");
        string memory saltStr = LibString.slice(result, saltIndex + 6, bytes(result).length);

        salt = bytes32(vm.parseUint(saltStr));
    }

    function saltWithAddressInFirst20Bytes(address addressToMakeSaltWith, uint256 suffix) internal pure returns (bytes32) {
        uint256 shifted = uint256(uint160(address(addressToMakeSaltWith))) << 96;

        // shifted on the left, suffix on the right:

        return bytes32(shifted | suffix);
    }

    function paramsFilePath(string memory proxyName) internal pure returns (string memory) {
        return string.concat("deterministicConfig/", proxyName, ".json");
    }

    function signaturesFilePath(string memory proxyName) internal pure returns (string memory) {
        return string.concat("deterministicConfig/", proxyName, "/signatures.json");
    }

    function serializeAndSaveOutput(DeterministicParams memory params, string memory proxyName) internal {
        string memory result = "deterministicKey";

        vm.serializeBytes(result, "proxyDeployerCreationCode", params.proxyDeployerCreationCode);
        vm.serializeBytes(result, "proxyCreationCode", params.proxyCreationCode);
        vm.serializeAddress(result, "deployerAddress", params.deployerAddress);
        vm.serializeAddress(result, "proxyDeployerAddress", params.proxyDeployerAddress);
        vm.serializeBytes32(result, "proxyDeployerSalt", params.proxyDeployerSalt);
        vm.serializeBytes32(result, "proxyShimSalt", params.proxyShimSalt);
        vm.serializeBytes32(result, "proxySalt", params.proxySalt);

        string memory finalOutput = vm.serializeAddress(result, "deterministicProxyAddress", params.deterministicProxyAddress);

        console2.log(finalOutput);

        vm.writeJson(finalOutput, paramsFilePath(proxyName));
    }

    function readDeterministicParams(string memory proxyName) internal view returns (DeterministicParams memory params) {
        string memory deployConfig = vm.readFile(paramsFilePath(proxyName));

        return
            DeterministicParams({
                proxyDeployerCreationCode: deployConfig.readBytes(".proxyDeployerCreationCode"),
                proxyCreationCode: deployConfig.readBytes(".proxyCreationCode"),
                deployerAddress: deployConfig.readAddress(".deployerAddress"),
                proxyDeployerAddress: deployConfig.readAddress(".proxyDeployerAddress"),
                proxyDeployerSalt: deployConfig.readBytes32(".proxyDeployerSalt"),
                proxyShimSalt: deployConfig.readBytes32(".proxyShimSalt"),
                proxySalt: deployConfig.readBytes32(".proxySalt"),
                deterministicProxyAddress: deployConfig.readAddress(".deterministicProxyAddress")
            });
    }

    function readDeterministicParamsAndSig(
        string memory proxyName,
        uint256 chain
    ) internal view returns (DeterministicParams memory params, bytes memory signature) {
        string memory signatures = vm.readFile(signaturesFilePath(proxyName));

        params = readDeterministicParams(proxyName);

        signature = signatures.readBytes(string.concat(".", string.concat(vm.toString(chain))));
    }

    function getProxyDeployerParams() internal view returns (bytes32 proxyDeployerSalt, bytes memory proxyDeployerCreationCode, address proxyDeployerAddress) {
        proxyDeployerSalt = ZoraDeployerUtils.FACTORY_DEPLOYER_DEPLOYMENT_SALT;

        proxyDeployerCreationCode = type(DeterministicProxyDeployer).creationCode;

        // we can know deterministically what the address of the new factory proxy deployer will be, given it's deployed from with the salt and init code,
        // from the ImmutableCreate2Factory
        proxyDeployerAddress = ImmutableCreate2FactoryUtils.immutableCreate2Address(proxyDeployerSalt, proxyDeployerCreationCode);
    }

    function getProxyShimParams(
        address proxyDeployerAddress,
        address deployerAddress,
        uint256 proxyShimSaltSuffix
    ) internal pure returns (bytes memory proxyShimInitCode, bytes32 proxyShimSalt, address proxyShimAddress) {
        proxyShimInitCode = abi.encodePacked(type(ProxyShim).creationCode, abi.encode(proxyDeployerAddress));

        // create any arbitrary salt for proxy shim (this can be anything, we just care about the resulting address)
        proxyShimSalt = saltWithAddressInFirst20Bytes(deployerAddress, proxyShimSaltSuffix);

        // now get deterministic proxy shim address based on salt, deployer address, which will be DeterministicProxyDeployer address and init code
        proxyShimAddress = Create2.computeAddress(proxyShimSalt, keccak256(proxyShimInitCode), proxyDeployerAddress);
    }

    function getProxyParams(
        bytes memory proxyCreationCode,
        address proxyShimAddress,
        address proxyDeployerAddress
    ) internal returns (bytes32 proxySalt, address deterministicProxyAddress) {
        bytes memory factoryProxyInitCode = abi.encodePacked(proxyCreationCode, abi.encode(proxyShimAddress, ""));
        bytes32 creationCodeHash = keccak256(factoryProxyInitCode);

        (proxySalt, deterministicProxyAddress) = mineSalt(proxyDeployerAddress, creationCodeHash, "777777");
    }

    function getDeterministicDeploymentParams(
        address deployerAddress,
        bytes memory proxyCreationCode,
        uint256 proxyShimSaltSuffix
    ) internal returns (DeterministicParams memory) {
        // 1. Get salt with first bytes that match address, and resulting deterministic factory proxy deployer address
        (bytes32 proxyDeployerSalt, bytes memory proxyDeployerCreationCode, address proxyDeployerAddress) = getProxyDeployerParams();
        // replace first 20 characters of salt with deployer address, so that the salt can be used with
        // ImmutableCreate2Factory.safeCreate2 when called by this deployer's account:

        // 2. Get random proxy shim salt, and resulting deterministic address
        // Proxy shim will be initialized with the factory deployer address as the owner, allowing only the factory deployer to upgrade the proxy,
        // to the eventual factory implementation
        (, bytes32 proxyShimSalt, address proxyShimAddress) = getProxyShimParams({
            proxyDeployerAddress: proxyDeployerAddress,
            deployerAddress: deployerAddress,
            proxyShimSaltSuffix: proxyShimSaltSuffix
        });

        // 3. Mine for a salt that can be used to deterministically create the factory proxy, given the proxy shim address, which is passed as the
        // constructor argument, and the deployer, which is the new factory proxy deployer, which we know the address of deterministically
        (bytes32 proxySalt, address deterministicProxyAddress) = getProxyParams({
            proxyCreationCode: proxyCreationCode,
            proxyShimAddress: proxyShimAddress,
            proxyDeployerAddress: proxyDeployerAddress
        });

        return
            DeterministicParams({
                proxyDeployerCreationCode: proxyDeployerCreationCode,
                proxyCreationCode: proxyCreationCode,
                deployerAddress: deployerAddress,
                proxyDeployerAddress: proxyDeployerAddress,
                proxyDeployerSalt: proxyDeployerSalt,
                proxyShimSalt: proxyShimSalt,
                proxySalt: proxySalt,
                deterministicProxyAddress: deterministicProxyAddress
            });
    }

    error MismatchedAddress(address expected, address actual);

    function readFactoryProxyDeterminsticParams() internal view returns (DeterministicParams memory) {
        return readDeterministicParams("factoryProxy");
    }

    function readPreminterProxyDeterminsticParams() internal view returns (DeterministicParams memory) {
        return readDeterministicParams("premintExecutorProxy");
    }

    function getOrCreateProxyDeployer() internal returns (DeterministicProxyDeployer factoryDeployer) {
        DeterministicParams memory params = readFactoryProxyDeterminsticParams();
        address proxyDeployerAddress = params.proxyDeployerAddress;
        bytes32 proxyDeployerSalt = params.proxyDeployerSalt;
        bytes memory proxyDeployerCreationCode = params.proxyDeployerCreationCode;

        address createdAddresss = ImmutableCreate2FactoryUtils.safeCreate2OrGetExisting(proxyDeployerSalt, proxyDeployerCreationCode);

        if (createdAddresss != proxyDeployerAddress) revert("Mismatched address");

        factoryDeployer = DeterministicProxyDeployer(proxyDeployerAddress);
    }

    function deployDeterministicProxy(string memory proxyName, address implementation, address owner, uint256 chain) internal returns (address) {
        (DeterministicParams memory params, bytes memory signature) = readDeterministicParamsAndSig(proxyName, chain);

        DeterministicProxyDeployer factoryDeployer = getOrCreateProxyDeployer();

        address resultAddress = factoryDeployer.createFactoryProxyDeterministic(
            params.proxyShimSalt,
            params.proxySalt,
            params.proxyCreationCode,
            params.deterministicProxyAddress,
            implementation,
            owner,
            signature
        );

        require(resultAddress == params.deterministicProxyAddress, "DeterministicDeployerScript: proxy address mismatch");

        return resultAddress;
    }

    function deployUpgradeGate(uint256 chain, address upgradeGateOwner) internal returns (address) {
        string memory signatures = vm.readFile(signaturesFilePath("upgradeGate"));
        bytes memory signature = signatures.readBytes(string.concat(".", string.concat(vm.toString(chain))));

        string memory upgradeGateParams = vm.readFile("./deterministicConfig/upgradeGate.json");

        bytes32 genericCreationSalt = vm.parseJsonBytes32(upgradeGateParams, ".salt");
        bytes memory creationCode = vm.parseJsonBytes(upgradeGateParams, ".creationCode");

        DeterministicProxyDeployer factoryDeployer = getOrCreateProxyDeployer();

        address resultAddress = factoryDeployer.createAndInitGenericContractDeterministic({
            genericCreationSalt: genericCreationSalt,
            creationCode: creationCode,
            initCall: abi.encodeWithSelector(UpgradeGate.initialize.selector, upgradeGateOwner),
            signature: signature
        });

        require(resultAddress == vm.parseJsonAddress(upgradeGateParams, ".upgradeGateAddress"), "DeterministicDeployerScript: upgrade gate address mismatch");

        return resultAddress;
    }
}
