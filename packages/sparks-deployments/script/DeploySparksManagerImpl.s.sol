// spdx-license-identifier: mit
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ZoraSparksManagerImpl} from "@zoralabs/sparks-contracts/src/ZoraSparksManagerImpl.sol";
import {SparksDeploymentConfig, SparksDeployment} from "../src/SparksDeploymentConfig.sol";
import {ProxyDeployerUtils} from "../src/ProxyDeployerUtils.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";

/// @dev Deploys a new sparks implementation at an expected determinstic address
contract DeploySparksManagerImpl is SparksDeploymentConfig {
    function run() public {
        SparksDeployment memory deploymentConfig = getDeployment();

        vm.startBroadcast();

        address sparksImplAddress = ImmutableCreate2FactoryUtils.safeCreate2OrGetExistingWithFriendlySalt(type(ZoraSparksManagerImpl).creationCode);

        vm.stopBroadcast();

        ZoraSparksManagerImpl sparksImpl = ZoraSparksManagerImpl(sparksImplAddress);

        deploymentConfig.sparksManagerImpl = sparksImplAddress;
        deploymentConfig.sparksImplVersion = sparksImpl.contractVersion();

        // save sparks deployment config
        saveDeployment(deploymentConfig);
    }
}
