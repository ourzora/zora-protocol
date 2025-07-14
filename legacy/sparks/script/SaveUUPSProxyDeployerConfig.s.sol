// spdx-license-identifier: mit
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ProxyDeployerScript} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";

/// @dev This saves the current bytecode, a salt, and an expected determinstic address for
/// the DeterministicUUPSProxyDeployer, to be used in subsequence scripts to generate
/// other deterministic parameters.
/// The resulting values in this file will affect downstream the resulting determinstic
/// deployed proxy addresses.
/// It should only be run if the code of the deployer changes and a new version needs to be deployed.
contract SaveUUPSProxyDeployerConfig is ProxyDeployerScript {
    function run() public {
        generateAndSaveUUPSProxyDeployerConfig();
    }
}
