// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ProxyDeployerScript, DeterministicDeployerAndCaller} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {CoinsDeployerBase} from "../src/deployment/CoinsDeployerBase.sol";
import {IHooksUpgradeGate} from "../src/interfaces/IHooksUpgradeGate.sol";

import {console} from "forge-std/console.sol";

contract DeployScript is CoinsDeployerBase {
    function run() public {
        CoinsDeployment memory deployment = readDeployment(false);

        address upgradeGate = deployment.hookUpgradeGate;

        address existingContentCoinHook = 0xd3D133469ADC85e01A4887404D8AC12d630e9040;
        address existingCreatorCoinHook = 0xffF800B76768dA8AB6aab527021e4a6A91219040;

        address target = deployment.hookUpgradeGate;

        address[] memory baseImpls = new address[](1);
        baseImpls[0] = existingContentCoinHook;

        bytes memory contentCoinUpgradeCall = abi.encodeWithSelector(IHooksUpgradeGate.registerUpgradePath.selector, baseImpls, deployment.zoraV4CoinHook);

        baseImpls[0] = existingCreatorCoinHook;

        bytes memory creatorCoinUpgradeCall = abi.encodeWithSelector(IHooksUpgradeGate.registerUpgradePath.selector, baseImpls, deployment.creatorCoinHook);

        console.log("target", target);

        console.log("contentCoinUpgradeCall");
        console.logBytes(contentCoinUpgradeCall);
        console.log("creatorCoinUpgradeCall");
        console.logBytes(creatorCoinUpgradeCall);
    }
}
