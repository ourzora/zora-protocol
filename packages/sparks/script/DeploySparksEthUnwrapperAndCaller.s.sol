// spdx-license-identifier: mit
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {SparksDeploymentConfig, SparksDeployment} from "../src/deployment/SparksDeploymentConfig.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";
import {SparksEthUnwrapperAndCaller} from "../src/helpers/SparksEthUnwrapperAndCaller.sol";

/// @dev Deploys a new sparks implementation at an expected determinstic address
contract DeploySparksUnwrapperAndColler is SparksDeploymentConfig {
    function run() public {
        SparksDeployment memory deploymentConfig = getDeployment();

        vm.startBroadcast();

        address sparks1155Address = getSparks1155Address();

        address unwrapperAddress = ImmutableCreate2FactoryUtils.safeCreate2OrGetExistingWithFriendlySalt(
            abi.encodePacked(type(SparksEthUnwrapperAndCaller).creationCode, abi.encode(sparks1155Address))
        );

        vm.stopBroadcast();

        deploymentConfig.sparksEthUnwrapperAndCaller = unwrapperAddress;

        // save sparks deployment config
        saveDeployment(deploymentConfig);
    }
}
