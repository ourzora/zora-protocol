// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ProxyDeployerScript, DeterministicDeployerAndCaller} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {CoinsDeployerBase} from "../src/deployment/CoinsDeployerBase.sol";

contract DeployScript is CoinsDeployerBase {
    function run() public {
        CoinsDeployment memory deployment = readDeployment(false);

        vm.startBroadcast();

        // get deployer contract
        deployment = deployUpgradeGate(deployment);

        vm.stopBroadcast();

        // save the deployment json
        saveDeployment(deployment);
    }
}
