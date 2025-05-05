// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CoinsDeployerBase} from "./CoinsDeployerBase.sol";
import {ZoraFactoryImpl} from "../src/ZoraFactoryImpl.sol";

contract UpgradeFactoryImpl is CoinsDeployerBase {
    function run() public {
        CoinsDeployment memory deployment = readDeployment();

        vm.startBroadcast();

        ZoraFactoryImpl zoraFactoryImpl = deployZoraFactoryImpl(deployment.coinImpl);

        deployment.zoraFactoryImpl = address(zoraFactoryImpl);

        vm.stopBroadcast();

        // save the deployment json
        saveDeployment(deployment);
        printUpgradeFactoryCommand(deployment);
    }
}
