// spdx-license-identifier: mit
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {Deployment, ChainConfig} from "./DeploymentConfig.sol";
import {ProxyShim} from "../utils/ProxyShim.sol";
import {NewFactoryProxyDeployer} from "./NewFactoryProxyDeployer.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ZoraDeployerUtils} from "./ZoraDeployerUtils.sol";

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
        return string.concat(string.concat("deterministicConfig/", proxyName), "/params.json");
    }

    function signaturesFilePath(string memory proxyName) internal pure returns (string memory) {
        return string.concat(string.concat("deterministicConfig/", proxyName), "/signatures.json");
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

    function readDeterministicParams(string memory proxyName, uint256 chain) internal view returns (DeterministicParams memory params, bytes memory signature) {
        string memory deployConfig = vm.readFile(paramsFilePath(proxyName));
        string memory signatures = vm.readFile(signaturesFilePath(proxyName));

        params = DeterministicParams({
            proxyDeployerCreationCode: deployConfig.readBytes(".proxyDeployerCreationCode"),
            proxyCreationCode: deployConfig.readBytes(".proxyCreationCode"),
            deployerAddress: deployConfig.readAddress(".deployerAddress"),
            proxyDeployerAddress: deployConfig.readAddress(".proxyDeployerAddress"),
            proxyDeployerSalt: deployConfig.readBytes32(".proxyDeployerSalt"),
            proxyShimSalt: deployConfig.readBytes32(".proxyShimSalt"),
            proxySalt: deployConfig.readBytes32(".proxySalt"),
            deterministicProxyAddress: deployConfig.readAddress(".deterministicProxyAddress")
        });

        signature = signatures.readBytes(string.concat(".", string.concat(vm.toString(chain))));
    }

    function getDeterministicDeploymentParams(
        address deployerAddress,
        bytes memory proxyCreationCode,
        uint256 proxyShimSaltSuffix
    ) internal returns (DeterministicParams memory) {
        // 1. Get salt with first bytes that match address, and resulting determinisitic factory proxy deployer address

        // replace first 20 characters of salt with deployer address, so that the salt can be used with
        // ImmutableCreate2Factory.safeCreate2 when called by this deployer's account:
        bytes32 proxyDeployerSalt = ZoraDeployerUtils.FACTORY_DEPLOYER_DEPLOYMENT_SALT;

        bytes memory proxyDeployerCreationCode = type(NewFactoryProxyDeployer).creationCode;

        // we can know deterministically what the address of the new factory proxy deployer will be, given it's deployed from with the salt and init code,
        // from the ImmutableCreate2Factory
        address proxyDeployerAddress = ZoraDeployerUtils.IMMUTABLE_CREATE2_FACTORY.findCreate2Address(proxyDeployerSalt, proxyDeployerCreationCode);

        console2.log("expected factory deployer address:", proxyDeployerAddress);

        // 2. Get random proxy shim salt, and resulting deterministic address

        // Proxy shim will be initialized with the factory deployer address as the owner, allowing only the factory deployer to upgrade the proxy,
        // to the eventual factory implementation
        bytes memory proxyShimInitCode = abi.encodePacked(type(ProxyShim).creationCode, abi.encode(proxyDeployerAddress));

        // create any arbitrary salt for proxy shim (this can be anything, we just care about the resulting address)
        bytes32 proxyShimSalt = saltWithAddressInFirst20Bytes(deployerAddress, proxyShimSaltSuffix);

        // now get deterministic proxy shim address based on salt, deployer address, which will be NewFactoryProxyDeployer address and init code
        address proxyShimAddress = Create2.computeAddress(proxyShimSalt, keccak256(proxyShimInitCode), proxyDeployerAddress);

        console2.log("proxy shim address:");
        console2.log(proxyShimAddress);

        // 3. Mine for a salt that can be used to deterministically create the factory proxy, given the proxy shim address, which is passed as the
        // constructor argument, and the deployer, which is the new factory proxy deployer, which we know the address of deterministically

        bytes memory factoryProxyInitCode = abi.encodePacked(proxyCreationCode, abi.encode(proxyShimAddress, ""));
        bytes32 creationCodeHash = keccak256(factoryProxyInitCode);

        console.log("init code hash: ", LibString.toHexStringNoPrefix(uint256(creationCodeHash), 32));

        (bytes32 proxySalt, address deterministicProxyAddress) = mineSalt(proxyDeployerAddress, creationCodeHash, "777777");

        DeterministicParams memory result = DeterministicParams({
            proxyDeployerCreationCode: proxyDeployerCreationCode,
            proxyCreationCode: proxyCreationCode,
            deployerAddress: deployerAddress,
            proxyDeployerAddress: proxyDeployerAddress,
            proxyDeployerSalt: proxyDeployerSalt,
            proxyShimSalt: proxyShimSalt,
            proxySalt: proxySalt,
            deterministicProxyAddress: deterministicProxyAddress
        });

        return result;
    }

    error MismatchedAddress(address expected, address actual);

    function deployDeterministicProxy(string memory proxyName, address implementation, address owner, uint256 chain) internal returns (address) {
        (DeterministicParams memory params, bytes memory signature) = readDeterministicParams(proxyName, chain);

        NewFactoryProxyDeployer factoryDeployer;

        if (ZoraDeployerUtils.IMMUTABLE_CREATE2_FACTORY.hasBeenDeployed(params.proxyDeployerAddress)) {
            factoryDeployer = NewFactoryProxyDeployer(params.proxyDeployerAddress);
        } else {
            factoryDeployer = NewFactoryProxyDeployer(
                ZoraDeployerUtils.IMMUTABLE_CREATE2_FACTORY.safeCreate2(params.proxyDeployerSalt, params.proxyDeployerCreationCode)
            );
        }

        console2.log(address(factoryDeployer));
        console2.log(params.proxyDeployerAddress);

        if (address(factoryDeployer) != params.proxyDeployerAddress) revert MismatchedAddress(params.proxyDeployerAddress, address(factoryDeployer));

        return
            factoryDeployer.createFactoryProxyDeterministic(
                params.proxyShimSalt,
                params.proxySalt,
                params.proxyCreationCode,
                params.deterministicProxyAddress,
                implementation,
                owner,
                signature
            );
    }
}
