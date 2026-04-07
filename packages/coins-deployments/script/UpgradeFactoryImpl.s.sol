// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CoinsDeployerBase} from "../src/deployment/CoinsDeployerBase.sol";
import {ZoraFactoryImpl} from "@zoralabs/coins/src/ZoraFactoryImpl.sol";

contract UpgradeFactoryImpl is CoinsDeployerBase {
    function run() public {
        CoinsDeployment memory deployment = readDeployment();

        require(deployment.coinV4Impl != address(0), "COIN_V4_IMPL not set");
        require(deployment.creatorCoinImpl != address(0), "CREATOR_COIN_IMPL not set");
        require(deployment.trendCoinImpl != address(0), "TREND_COIN_IMPL not set");
        require(deployment.zoraV4CoinHook != address(0), "ZORA_V4_COIN_HOOK not set");
        require(deployment.zoraHookRegistry != address(0), "ZORA_HOOK_REGISTRY not set");

        vm.startBroadcast();

        ZoraFactoryImpl zoraFactoryImpl = deployZoraFactoryImpl(
            deployment.coinV4Impl,
            deployment.creatorCoinImpl,
            deployment.trendCoinImpl,
            deployment.zoraV4CoinHook,
            deployment.zoraHookRegistry
        );

        deployment.zoraFactoryImpl = address(zoraFactoryImpl);

        vm.stopBroadcast();

        // save the deployment json
        saveDeployment(deployment);
        printUpgradeFactoryCommand(deployment);
    }
}
