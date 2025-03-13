// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ProxyDeployerScript, DeterministicDeployerAndCaller} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {CoinsDeployerBase} from "./CoinsDeployerBase.sol";

contract UpgradeCoinImpl is CoinsDeployerBase {
    function run() public {
        CoinsDeployment memory deployment = readDeployment();

        vm.startBroadcast();

        // get deployer contract
        DeterministicDeployerAndCaller deployer = createOrGetDeployerAndCaller();

        deployment = deployImpls(deployment);

        vm.stopBroadcast();

        // save the deployment json
        saveDeployment(deployment);
    }
}
