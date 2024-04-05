// spdx-license-identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import {LibString} from "solady/utils/LibString.sol";

import {ProxyDeployerConfig, MintsDeterministicConfig, DeterminsticContractConfig} from "./Config.sol";
import {ProxyDeployerUtils} from "../src/ProxyDeployerUtils.sol";
import {DeterministicUUPSProxyDeployer} from "./DeterministicUUPSProxyDeployer.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";

contract ProxyDeployerScript is Script {
    using stdJson for string;

    string constant PROXY_DEPLOYER_CONFIG_PATH = "deterministicConfig/proxyDeployer/params.json";

    function readProxyDeployerConfig() internal view returns (ProxyDeployerConfig memory config) {
        string memory json = vm.readFile(PROXY_DEPLOYER_CONFIG_PATH);

        config.creationCode = json.readBytes(".creationCode");
        config.salt = json.readBytes32(".salt");
        config.deployedAddress = json.readAddress(".deployedAddress");
    }

    function writeProxyDeployerConfig(ProxyDeployerConfig memory config) internal {
        string memory result = "deterministicKey";

        vm.serializeAddress(result, "deployedAddress", config.deployedAddress);
        vm.serializeBytes(result, "creationCode", config.creationCode);
        string memory finalOutput = vm.serializeBytes32(result, "salt", config.salt);

        vm.writeJson(finalOutput, "deterministicConfig/proxyDeployer/params.json");
    }

    function determinsticConfigJson(DeterminsticContractConfig memory config, string memory objectKey) internal returns (string memory result) {
        vm.serializeBytes32(objectKey, "salt", config.salt);
        vm.serializeBytes(objectKey, "creationCode", config.creationCode);
        vm.serializeAddress(objectKey, "deployedAddress", config.deployedAddress);
        vm.serializeString(objectKey, "contractName", config.contractName);
        result = vm.serializeBytes(objectKey, "constructorArgs", config.constructorArgs);
    }

    function writeMintsMintsDeterministicConfig(MintsDeterministicConfig memory config, string memory proxyName) internal {
        string memory key = "some key";
        vm.serializeAddress(key, "deploymentCaller", config.deploymentCaller);

        vm.serializeString(key, "manager", determinsticConfigJson(config.manager, "manager"));
        string memory finalJson = vm.serializeString(key, "mints1155", determinsticConfigJson(config.mints1155, "mints1155"));

        vm.writeJson(finalJson, string.concat(string.concat("deterministicConfig/", proxyName, "/params.json")));
    }

    function createOrGetDeterministicProxyDeployer() internal returns (DeterministicUUPSProxyDeployer) {
        ProxyDeployerConfig memory proxyDeployerConfig = readProxyDeployerConfig();

        return ProxyDeployerUtils.createOrGetProxyDeployer(proxyDeployerConfig);
    }
}
