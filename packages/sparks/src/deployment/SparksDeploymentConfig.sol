// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Script} from "forge-std/Script.sol";
import {DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/Config.sol";
import {ProxyDeployerScript} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";

struct SparksDeployment {
    address sparksManager;
    address sparks1155;
    address mintsManager;
    address mints1155;
    address sparksManagerImpl;
    string sparksImplVersion;
    address sparksEthUnwrapperAndCaller;
    address sponsoredSparksSpender;
    string sponsoredSparksSpenderVersion;
}

// config for deploying the Sparks proxy,
// this should be the same on all chains
struct SparksDeterministicConfig {
    address deploymentCaller;
    DeterministicContractConfig manager;
    DeterministicContractConfig sparks1155;
}

abstract contract SparksDeploymentConfig is ProxyDeployerScript {
    using stdJson for string;

    string constant SPARKS_MANAGER = "SPARKS_MANAGER";
    string constant SPARKS_1155 = "SPARKS_1155";
    string constant MINTS_MANAGER = "MINTS_MANAGER";
    string constant MINTS_1155 = "MINTS_1155";
    string constant SPARKS_MANAGER_IMPL = "SPARKS_MANAGER_IMPL";
    string constant SPARKS_MANAGER_IMPL_VERSION = "SPARKS_MANAGER_IMPL_VERSION";
    string constant MINTS_ETH_UNWRAPPER_AND_CALLER = "MINTS_ETH_UNWRAPPER_AND_CALLER";
    string constant SPONSORED_SPARKS_SPENDER = "SPONSORED_SPARKS_SPENDER";
    string constant SPONSORED_SPARKS_SPENDER_VERSION = "SPONSORED_SPARKS_SPENDER_VERSION";

    function saveDeployment(SparksDeployment memory sparksDeployment) internal {
        string memory result = "sparksDeployment";

        vm.serializeAddress(result, SPARKS_MANAGER_IMPL, sparksDeployment.sparksManagerImpl);
        vm.serializeAddress(result, SPARKS_MANAGER, sparksDeployment.sparksManager);
        vm.serializeAddress(result, SPARKS_1155, sparksDeployment.sparks1155);
        vm.serializeAddress(result, MINTS_MANAGER, sparksDeployment.mintsManager);
        vm.serializeAddress(result, MINTS_1155, sparksDeployment.mints1155);
        vm.serializeAddress(result, MINTS_ETH_UNWRAPPER_AND_CALLER, sparksDeployment.sparksEthUnwrapperAndCaller);
        vm.serializeAddress(result, SPONSORED_SPARKS_SPENDER, sparksDeployment.sponsoredSparksSpender);
        vm.serializeString(result, SPONSORED_SPARKS_SPENDER_VERSION, sparksDeployment.sponsoredSparksSpenderVersion);
        string memory finalOutput = vm.serializeString(result, SPARKS_MANAGER_IMPL_VERSION, sparksDeployment.sparksImplVersion);

        vm.writeJson(finalOutput, string.concat(string.concat("addresses/", vm.toString(block.chainid)), ".json"));
    }

    function getDeployment() internal returns (SparksDeployment memory) {
        string memory path = string.concat(string.concat("addresses/", vm.toString(block.chainid)), ".json");
        string memory json = vm.isFile(path) ? vm.readFile(path) : "{}";

        return
            SparksDeployment({
                sparksManagerImpl: readAddressOrDefaultToZero(json, SPARKS_MANAGER_IMPL),
                sparksImplVersion: readStringOrDefaultToEmpty(json, SPARKS_MANAGER_IMPL_VERSION),
                sparksManager: readAddressOrDefaultToZero(json, SPARKS_MANAGER),
                sparks1155: readAddressOrDefaultToZero(json, SPARKS_1155),
                mintsManager: readAddressOrDefaultToZero(json, MINTS_MANAGER),
                mints1155: readAddressOrDefaultToZero(json, MINTS_1155),
                sparksEthUnwrapperAndCaller: readAddressOrDefaultToZero(json, MINTS_ETH_UNWRAPPER_AND_CALLER),
                sponsoredSparksSpender: readAddressOrDefaultToZero(json, SPONSORED_SPARKS_SPENDER),
                sponsoredSparksSpenderVersion: readStringOrDefaultToEmpty(json, SPONSORED_SPARKS_SPENDER_VERSION)
            });
    }

    function getSparks1155Address() internal view returns (address) {
        string memory sparksProxyConfig = "deterministicConfig/sparksProxy/params.json";

        string memory json = vm.readFile(sparksProxyConfig);

        return json.readAddress(".sparks1155.deployedAddress");
    }

    function writeSparksSparksDeterministicConfig(SparksDeterministicConfig memory config, string memory proxyName) internal {
        string memory key = "some key";

        vm.serializeString(key, "manager", determinsticConfigJson(config.manager, "manager"));
        string memory finalJson = vm.serializeString(key, "sparks1155", determinsticConfigJson(config.sparks1155, "sparks1155"));

        vm.writeJson(finalJson, string.concat(string.concat("deterministicConfig/", proxyName, "/params.json")));
    }
}
