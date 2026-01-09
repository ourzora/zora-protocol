// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CoinsDeployerBase} from "../src/deployment/CoinsDeployerBase.sol";

contract DeployTrustedMsgSenderLookup is CoinsDeployerBase {
    function run() public {
        CoinsDeployment memory deployment = readDeployment();

        vm.startBroadcast();

        // Deploy the trusted message sender lookup contract
        deployment = deployTrustedMsgSenderLookup(deployment);

        vm.stopBroadcast();

        // Save the updated deployment json
        saveDeployment(deployment);
    }
}
