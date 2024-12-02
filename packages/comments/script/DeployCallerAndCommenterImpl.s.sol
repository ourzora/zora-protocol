// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import {CommentsDeployerBase} from "./CommentsDeployerBase.sol";
import {CallerAndCommenterImpl} from "../src/utils/CallerAndCommenterImpl.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract DeployCallerAndCommenterImpl is CommentsDeployerBase {
    function run() public {
        CommentsDeployment memory config = readDeployment();

        vm.startBroadcast();

        config.callerAndCommenterImpl = deployCallerAndCommenterImpl(config.comments);
        config.callerAndCommenterVersion = CallerAndCommenterImpl(config.callerAndCommenterImpl).contractVersion();

        vm.stopBroadcast();

        console2.log("CallerAndCommenterImpl deployed, to upgrade:");
        console2.log("target:", config.callerAndCommenter);
        console2.log("calldata:");
        console2.logBytes(abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, config.callerAndCommenterImpl, ""));
        console2.log("multisig:", getProxyAdmin());

        saveDeployment(config);
    }
}
