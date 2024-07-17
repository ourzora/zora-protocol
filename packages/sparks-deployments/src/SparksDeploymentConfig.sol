// SPDX-License-Identifier: MIT

import "forge-std/Test.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Script} from "forge-std/Script.sol";

struct SparksDeployment {
    address sparksManagerImpl;
    string sparksImplVersion;
    address sparksEthUnwrapperAndCaller;
}

abstract contract SparksDeploymentConfig is Script {
    using stdJson for string;

    string constant SPARKS_MANAGER_IMPL = "SPARKS_MANAGER_IMPL";
    string constant SPARKS_MANAGER_IMPL_VERSION = "SPARKS_MANAGER_IMPL_VERSION";
    string constant MINTS_ETH_UNWRAPPER_AND_CALLER = "MINTS_ETH_UNWRAPPER_AND_CALLER";

    function saveDeployment(SparksDeployment memory sparksDeployment) internal {
        string memory result = "sparksDeployment";

        vm.serializeAddress(result, SPARKS_MANAGER_IMPL, sparksDeployment.sparksManagerImpl);
        vm.serializeAddress(result, MINTS_ETH_UNWRAPPER_AND_CALLER, sparksDeployment.sparksEthUnwrapperAndCaller);
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

    function getDeployment() internal view returns (SparksDeployment memory) {
        string memory json = vm.readFile(string.concat(string.concat("addresses/", vm.toString(block.chainid)), ".json"));

        return
            SparksDeployment({
                sparksManagerImpl: readAddressOrDefaultToZero(json, SPARKS_MANAGER_IMPL),
                sparksImplVersion: json.readString(getKeyPrefix(SPARKS_MANAGER_IMPL_VERSION)),
                sparksEthUnwrapperAndCaller: readAddressOrDefaultToZero(json, MINTS_ETH_UNWRAPPER_AND_CALLER)
            });
    }

    function getSparks1155Address() internal view returns (address) {
        string memory sparksProxyConfig = "deterministicConfig/sparksProxy/params.json";

        string memory json = vm.readFile(sparksProxyConfig);

        return json.readAddress(".sparks1155.deployedAddress");
    }
}
