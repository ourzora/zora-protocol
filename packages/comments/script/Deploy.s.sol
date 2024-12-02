// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ProxyDeployerScript, DeterministicDeployerAndCaller, DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {CommentsDeployerBase} from "./CommentsDeployerBase.sol";

contract DeployScript is CommentsDeployerBase {
    function run() public {
        CommentsDeployment memory deployment = readDeployment();

        vm.startBroadcast();

        // get deployer contract
        DeterministicDeployerAndCaller deployer = createOrGetDeployerAndCaller();

        deployCommentsDeterministic(deployment, deployer);
        deployCallerAndCommenterDeterministic(deployment, deployer);

        vm.stopBroadcast();

        // save the deployment json
        saveDeployment(deployment);
    }
}
