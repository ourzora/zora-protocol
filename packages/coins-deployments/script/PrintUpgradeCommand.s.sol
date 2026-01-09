// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ProxyDeployerScript, DeterministicDeployerAndCaller} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {CoinsDeployerBase} from "../src/deployment/CoinsDeployerBase.sol";

contract PrintUpgradeCommand is CoinsDeployerBase {
    function run() public {
        CoinsDeployment memory deployment = readDeployment();

        printUpgradeFactoryCommand(deployment);
    }
}
