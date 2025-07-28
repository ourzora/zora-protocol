// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CoinsDeployerBase} from "../src/deployment/CoinsDeployerBase.sol";
import {ZoraFactoryImpl} from "../src/ZoraFactoryImpl.sol";

contract DeployHooks is CoinsDeployerBase {
    function run() public {
        CoinsDeployment memory deployment = readDeployment();

        vm.startBroadcast();

        // address buySupplyWithSwapRouterHook = address(deployBuySupplyWithSwapRouterHook(deployment));

        // deployment.buySupplyWithSwapRouterHook = buySupplyWithSwapRouterHook;

        vm.stopBroadcast();

        // save the deployment json
        saveDeployment(deployment);
    }
}
