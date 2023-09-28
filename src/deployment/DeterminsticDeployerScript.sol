// spdx-license-identifier: mit
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {Deployment, ChainConfig} from "./DeploymentConfig.sol";
import {ProxyShim} from "../utils/ProxyShim.sol";
import {NewFactoryProxyDeployer} from "./NewFactoryProxyDeployer.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ZoraDeployer} from "./ZoraDeployer.sol";

struct DeterminsticParams {
    bytes proxyDeployerCreationCode;
    bytes proxyCreationCode;
    address deployerAddress;
    address proxyDeployerAddress;
    bytes32 proxyDeployerSalt;
    bytes32 proxyShimSalt;
    bytes32 proxySalt;
    address determinsticProxyAddress;
}

contract DeterminsticDeployerScript is Script {
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

    function saltWithAddressInFirst20Bytes(address addressToMakeSaltWith) internal pure returns (bytes32) {
        uint256 shifted = uint256(uint160(address(addressToMakeSaltWith))) << 96;

        return bytes32(shifted);
    }

    function serializeAndSaveOutput(DeterminsticParams memory params) internal {
        string memory result = "determinsitc_key";

        vm.serializeBytes(result, "proxyDeployerCreationCode", params.proxyDeployerCreationCode);
        vm.serializeBytes(result, "proxyCreationCode", params.proxyCreationCode);
        vm.serializeAddress(result, "deployerAddress", params.deployerAddress);
        vm.serializeAddress(result, "proxyDeployerAddress", params.proxyDeployerAddress);
        vm.serializeBytes32(result, "proxyDeployerSalt", params.proxyDeployerSalt);
        vm.serializeBytes32(result, "proxyShimSalt", params.proxyShimSalt);
        vm.serializeBytes32(result, "proxySalt", params.proxySalt);

        string memory finalOutput = vm.serializeAddress(result, "determinsticProxyAddress", params.determinsticProxyAddress);

        console2.log(finalOutput);

        vm.writeJson(finalOutput, "determinsticConfig/factoryProxy/params.json");
    }

    function readDeterminsticParams(string memory proxyName, uint256 chain) internal returns (DeterminsticParams memory params, bytes memory signature) {
        string memory root = vm.projectRoot();
        string memory folder = string.concat(string.concat(root, "/determinsticConfig/"), proxyName);
        string memory deployConfig = vm.readFile(string.concat(folder, "/params.json"));
        string memory signatures = vm.readFile(string.concat(folder, "/signatures.json"));

        params = DeterminsticParams({
            proxyDeployerCreationCode: deployConfig.readBytes(".proxyDeployerCreationCode"),
            proxyCreationCode: deployConfig.readBytes(".proxyCreationCode"),
            deployerAddress: deployConfig.readAddress(".deployerAddress"),
            proxyDeployerAddress: deployConfig.readAddress(".proxyDeployerAddress"),
            proxyDeployerSalt: deployConfig.readBytes32(".proxyDeployerSalt"),
            proxyShimSalt: deployConfig.readBytes32(".proxyShimSalt"),
            proxySalt: deployConfig.readBytes32(".proxySalt"),
            determinsticProxyAddress: deployConfig.readAddress(".determinsticProxyAddress")
        });

        signature = signatures.readBytes(string.concat(".", string.concat(vm.toString(chain))));
    }

    function getDeterminsticDeploymentParams(
        address deployerAddress,
        bytes memory proxyCreationCode
    )
        internal
        returns (
            bytes32 newFactoryProxyDeployerSalt,
            bytes memory newFactoryProxyDeployerInitCode,
            address proxyDeployerContractAddress,
            bytes32 proxyShimSalt,
            bytes32 proxySalt,
            address determinsticProxyAddress
        )
    {
        // 1. Get salt with first bytes that match address, and resulting determinsitic factory proxy deployer address

        // replace first 20 characters of salt with deployer address, so that the salt can be used with
        // ImmutableCreate2Factory.safeCreate2 when called by this deployer's account:
        newFactoryProxyDeployerSalt = ZoraDeployer.FACTORY_DEPLOYER_DEPLOYMENT_SALT;

        newFactoryProxyDeployerInitCode = type(NewFactoryProxyDeployer).creationCode;

        // we can know determinstically what the address of the new factory proxy deployer will be, given it's deployed from with the salt and init code,
        // from the ImmutableCreate2Factory
        proxyDeployerContractAddress = ZoraDeployer.IMMUTABLE_CREATE2_FACTORY.findCreate2Address(newFactoryProxyDeployerSalt, newFactoryProxyDeployerInitCode);

        console2.log("expected factory deployer address:", proxyDeployerContractAddress);

        // 2. Get random proxy shim salt, and resulting determinstic address

        // Proxy shim will be initialized with the factory deployer address as the owner, allowing only the factory deployer to upgrade the proxy,
        // to the eventual factory implementation
        bytes memory proxyShimInitCode = abi.encodePacked(type(ProxyShim).creationCode, abi.encode(proxyDeployerContractAddress));

        // create any arbitrary salt for proxy shim (this can be anything, we just care about the resulting address)
        proxyShimSalt = saltWithAddressInFirst20Bytes(deployerAddress);

        // now get determinstic proxy shim address based on salt, deployer address, which will be NewFactoryProxyDeployer address and init code
        address proxyShimAddress = Create2.computeAddress(proxyShimSalt, keccak256(proxyShimInitCode), proxyDeployerContractAddress);

        console2.log("proxy shim address:");
        console2.log(proxyShimAddress);

        // 3. Mine for a salt that can be used to determinstically create the factory proxy, given the proxy shim address, which is passed as the
        // constructor argument, and the deployer, which is the new factory proxy deployer, which we know the address of determinstically

        bytes memory factoryProxyInitCode = abi.encodePacked(proxyCreationCode, abi.encode(proxyShimAddress, ""));
        bytes32 creationCodeHash = keccak256(factoryProxyInitCode);

        console.log("init code hash: ", LibString.toHexStringNoPrefix(uint256(creationCodeHash), 32));

        (proxySalt, determinsticProxyAddress) = mineSalt(proxyDeployerContractAddress, creationCodeHash, "777777");
    }
}
