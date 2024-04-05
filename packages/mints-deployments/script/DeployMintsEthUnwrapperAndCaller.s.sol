// spdx-license-identifier: mit
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MintsDeploymentConfig, MintsDeployment} from "../src/MintsDeploymentConfig.sol";
import {ProxyDeployerUtils} from "../src/ProxyDeployerUtils.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";
import {MintsEthUnwrapperAndCaller} from "@zoralabs/mints-contracts/src/helpers/MintsEthUnwrapperAndCaller.sol";

/// @dev Deploys a new mints implementation at an expected determinstic address
contract DeployMintsUnwrapperAndColler is MintsDeploymentConfig {
    function run() public {
        MintsDeployment memory deploymentConfig = getDeployment();

        vm.startBroadcast();

        address mints1155Address = getMints1155Address();

        address unwrapperAddress = ImmutableCreate2FactoryUtils.safeCreate2OrGetExistingWithFriendlySalt(
            abi.encodePacked(type(MintsEthUnwrapperAndCaller).creationCode, abi.encode(mints1155Address))
        );

        vm.stopBroadcast();

        deploymentConfig.mintsEthUnwrapperAndCaller = unwrapperAddress;

        // save mints deployment config
        saveDeployment(deploymentConfig);
    }
}
