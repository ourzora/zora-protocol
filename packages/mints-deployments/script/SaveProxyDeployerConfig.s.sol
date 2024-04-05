// spdx-license-identifier: mit
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {DeterministicUUPSProxyDeployer} from "../src/DeterministicUUPSProxyDeployer.sol";
import {ProxyDeployerConfig} from "../src/ProxyDeployerUtils.sol";
import {ProxyDeployerScript} from "../src/ProxyDeployerScript.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";

/// @dev This saves the current bytecode, a salt, and an expected determinstic address for
/// the DeterministicUUPSProxyDeployer, to be used in subsequence scripts to generate
/// other determistic parameters.
/// The resulting values in this file will affect downstream the resulting determinstic
/// deployed proxy addresses.
/// It should only be run if the code of the deployer changes and a new version needs to be deployed.
contract SaveProxyDeployerConfig is ProxyDeployerScript {
    function run() public {
        bytes32 salt = ImmutableCreate2FactoryUtils.IMMUTABLE_CREATE_2_FRIENDLY_SALT;
        bytes memory creationCode = type(DeterministicUUPSProxyDeployer).creationCode;
        address deterministicAddress = ImmutableCreate2FactoryUtils.immutableCreate2Address(creationCode);

        ProxyDeployerConfig memory config = ProxyDeployerConfig({creationCode: creationCode, salt: salt, deployedAddress: deterministicAddress});

        writeProxyDeployerConfig(config);
    }
}
