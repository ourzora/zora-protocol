// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ProxyDeployerScript, DeterministicDeployerAndCaller} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {CoinsDeployerBase} from "./CoinsDeployerBase.sol";

contract DeployScript is CoinsDeployerBase {
    function run() public {
        CoinsDeployment memory deployment = readDeployment();

        vm.startBroadcast();

        // get deployer contract
        DeterministicDeployerAndCaller deployer = createOrGetDeployerAndCaller();

        address newCoinImpl = address(deployCoinImpl());

        deployment.coinImpl = newCoinImpl;

        vm.stopBroadcast();

        // save the deployment json
        saveDeployment(deployment);
    }
}
