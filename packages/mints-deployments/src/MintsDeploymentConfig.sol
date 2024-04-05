// SPDX-License-Identifier: MIT

import "forge-std/Test.sol";
import {CommonBase} from "forge-std/Base.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Script} from "forge-std/Script.sol";

struct MintsDeployment {
    address mintsManagerImpl;
    string mintsImplVersion;
    address mintsEthUnwrapperAndCaller;
}

abstract contract MintsDeploymentConfig is Script {
    using stdJson for string;

    string constant MINTS_MANAGER_IMPL = "MINTS_MANAGER_IMPL";
    string constant MINTS_MANAGER_IMPL_VERSION = "MINTS_MANAGER_IMPL_VERSION";
    string constant MINTS_ETH_UNWRAPPER_AND_CALLER = "MINTS_ETH_UNWRAPPER_AND_CALLER";

    function saveDeployment(MintsDeployment memory mintsDeployment) internal {
        string memory result = "mintsDeployment";

        vm.serializeAddress(result, MINTS_MANAGER_IMPL, mintsDeployment.mintsManagerImpl);
        vm.serializeAddress(result, MINTS_ETH_UNWRAPPER_AND_CALLER, mintsDeployment.mintsEthUnwrapperAndCaller);
        string memory finalOutput = vm.serializeString(result, MINTS_MANAGER_IMPL_VERSION, mintsDeployment.mintsImplVersion);

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

    function getDeployment() internal view returns (MintsDeployment memory) {
        string memory json = vm.readFile(string.concat(string.concat("addresses/", vm.toString(block.chainid)), ".json"));

        return
            MintsDeployment({
                mintsManagerImpl: readAddressOrDefaultToZero(json, MINTS_MANAGER_IMPL),
                mintsImplVersion: json.readString(getKeyPrefix(MINTS_MANAGER_IMPL_VERSION)),
                mintsEthUnwrapperAndCaller: readAddressOrDefaultToZero(json, MINTS_ETH_UNWRAPPER_AND_CALLER)
            });
    }

    function getMints1155Address() internal view returns (address) {
        string memory mintsProxyConfig = "deterministicConfig/mintsProxy/params.json";

        string memory json = vm.readFile(mintsProxyConfig);

        return json.readAddress(".mints1155.deployedAddress");
    }
}
