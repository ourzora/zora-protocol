// spdx-license-identifier: mit
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ZoraMintsManagerImpl} from "@zoralabs/mints-contracts/src/ZoraMintsManagerImpl.sol";
import {MintsDeploymentConfig, MintsDeployment} from "../src/MintsDeploymentConfig.sol";
import {ProxyDeployerUtils} from "../src/ProxyDeployerUtils.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";

/// @dev Deploys a new mints implementation at an expected determinstic address
contract DeployMintsManagerImpl is MintsDeploymentConfig {
    function run() public {
        MintsDeployment memory deploymentConfig = getDeployment();

        vm.startBroadcast();

        address preminterProxyAddress = 0x7777773606e7e46C8Ba8B98C08f5cD218e31d340;

        address mintsImplAddress = ImmutableCreate2FactoryUtils.safeCreate2OrGetExistingWithFriendlySalt(
            abi.encodePacked(type(ZoraMintsManagerImpl).creationCode, abi.encode(preminterProxyAddress))
        );

        vm.stopBroadcast();

        ZoraMintsManagerImpl mintsImpl = ZoraMintsManagerImpl(mintsImplAddress);

        deploymentConfig.mintsManagerImpl = mintsImplAddress;
        deploymentConfig.mintsImplVersion = mintsImpl.contractVersion();

        // save mints deployment config
        saveDeployment(deploymentConfig);
    }
}
