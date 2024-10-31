// SPDX-License-Identifier: MIT

import "forge-std/Test.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Script} from "forge-std/Script.sol";

struct SparksDeployment {
    address sparksManagerImpl;
    string sparksImplVersion;
    address sparksEthUnwrapperAndCaller;
    address sponsoredSparksSpender;
    string sponsoredSparksSpenderVersion;
}

abstract contract SparksDeploymentConfig is Script {
    using stdJson for string;

    string constant SPARKS_MANAGER_IMPL = "SPARKS_MANAGER_IMPL";
    string constant SPARKS_MANAGER_IMPL_VERSION = "SPARKS_MANAGER_IMPL_VERSION";
    string constant MINTS_ETH_UNWRAPPER_AND_CALLER = "MINTS_ETH_UNWRAPPER_AND_CALLER";
    string constant SPONSORED_SPARKS_SPENDER = "SPONSORED_SPARKS_SPENDER";
    string constant SPONSORED_SPARKS_SPENDER_VERSION = "SPONSORED_SPARKS_SPENDER_VERSION";

    function saveDeployment(SparksDeployment memory sparksDeployment) internal {
        string memory result = "sparksDeployment";

        vm.serializeAddress(result, SPARKS_MANAGER_IMPL, sparksDeployment.sparksManagerImpl);
        vm.serializeAddress(result, MINTS_ETH_UNWRAPPER_AND_CALLER, sparksDeployment.sparksEthUnwrapperAndCaller);
        vm.serializeAddress(result, SPONSORED_SPARKS_SPENDER, sparksDeployment.sponsoredSparksSpender);
        vm.serializeString(result, SPONSORED_SPARKS_SPENDER_VERSION, sparksDeployment.sponsoredSparksSpenderVersion);
        string memory finalOutput = vm.serializeString(result, SPARKS_MANAGER_IMPL_VERSION, sparksDeployment.sparksImplVersion);

        vm.writeJson(finalOutput, string.concat(string.concat("addresses/", vm.toString(block.chainid)), ".json"));
    }

    /// @notice Return a prefixed key for reading with a ".".
    /// @param key key to prefix
    /// @return prefixed key
    function getKeyPrefix(string memory key) internal pure returns (string memory) {
        return string.concat(".", key);
    }

    function readAddressOrDefaultToZero(string memory json, string memory key) internal view returns (address addr) {
        string memory keyPrefix = getKeyPrefix(key);

        if (vm.keyExists(json, keyPrefix)) {
            addr = json.readAddress(keyPrefix);
        } else {
            addr = address(0);
        }
    }

    function readStringOrDefaultToZero(string memory json, string memory key) internal view returns (string memory str) {
        string memory keyPrefix = getKeyPrefix(key);

        if (vm.keyExists(json, keyPrefix)) {
            str = json.readString(keyPrefix);
        } else {
            str = "";
        }
    }

    function getDeployment() internal returns (SparksDeployment memory) {
        string memory path = string.concat(string.concat("addresses/", vm.toString(block.chainid)), ".json");
        string memory json = vm.isFile(path) ? vm.readFile(path) : "{}";

        return
            SparksDeployment({
                sparksManagerImpl: readAddressOrDefaultToZero(json, SPARKS_MANAGER_IMPL),
                sparksImplVersion: readStringOrDefaultToZero(json, SPARKS_MANAGER_IMPL_VERSION),
                sparksEthUnwrapperAndCaller: readAddressOrDefaultToZero(json, MINTS_ETH_UNWRAPPER_AND_CALLER),
                sponsoredSparksSpender: readAddressOrDefaultToZero(json, SPONSORED_SPARKS_SPENDER),
                sponsoredSparksSpenderVersion: readStringOrDefaultToZero(json, SPONSORED_SPARKS_SPENDER_VERSION)
            });
    }

    function getSparks1155Address() internal view returns (address) {
        string memory sparksProxyConfig = "deterministicConfig/sparksProxy/params.json";

        string memory json = vm.readFile(sparksProxyConfig);

        return json.readAddress(".sparks1155.deployedAddress");
    }
}
