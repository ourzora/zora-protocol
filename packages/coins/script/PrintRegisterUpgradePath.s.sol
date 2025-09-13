// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ProxyDeployerScript, DeterministicDeployerAndCaller} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {CoinsDeployerBase} from "../src/deployment/CoinsDeployerBase.sol";
import {IHooksUpgradeGate} from "../src/interfaces/IHooksUpgradeGate.sol";

import {console} from "forge-std/console.sol";

contract DeployScript is CoinsDeployerBase {
    function run() public {
        CoinsDeployment memory deployment = readDeployment(false);

        address existingContentCoinHook = 0xd3D133469ADC85e01A4887404D8AC12d630e9040;

        address[] memory baseImpls = new address[](1);
        baseImpls[0] = existingContentCoinHook;

        bytes memory contentCoinUpgradeCall = abi.encodeWithSelector(IHooksUpgradeGate.registerUpgradePath.selector, baseImpls, deployment.zoraV4CoinHook);

        printUpgradeFactoryCommand(deployment);

        console.log("register upgrade gate target", deployment.hookUpgradeGate);

        console.log("contentCoinUpgradeCall");
        console.logBytes(contentCoinUpgradeCall);
    }
}
