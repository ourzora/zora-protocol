// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import {CommentsDeployerBase} from "./CommentsDeployerBase.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract DeployImpl is CommentsDeployerBase {
    function run() public {
        CommentsDeployment memory config = readDeployment();
        vm.startBroadcast();

        config.commentsImpl = address(deployCommentsImpl());
        config.commentsImplBlockNumber = block.number;

        vm.stopBroadcast();

        console2.log("CommentsImpl deployed, to upgrade:");
        console2.log("target:", config.comments);
        console2.log("calldata:");
        console2.logBytes(abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, config.commentsImpl, ""));
        console2.log("multisig:", getProxyAdmin());

        saveDeployment(config);
    }
}
