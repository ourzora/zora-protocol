// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Comments} from "../src/proxy/Comments.sol";
import {CommentsImpl} from "../src/CommentsImpl.sol";
import {CommentsDeployerBase} from "./CommentsDeployerBase.sol";
import {CallerAndCommenterImpl} from "../src/utils/CallerAndCommenterImpl.sol";
import {CallerAndCommenter} from "../src/proxy/CallerAndCommenter.sol";

contract DeployNonDeterministic is CommentsDeployerBase {
    function run() public {
        CommentsDeployment memory deployment = readDeployment();

        address owner = getProxyAdmin();

        address backfiller = CommentsDeployerBase.getBackfillerAccount();

        vm.startBroadcast();

        address implAddress = deployment.commentsImpl;

        if (implAddress.code.length == 0) {
            revert("impl not deployed");
        }

        Comments comments = new Comments(implAddress);

        CallerAndCommenterImpl callerAndCommenterImpl = new CallerAndCommenterImpl(address(comments), ZORA_TIMED_SALE_STRATEGY, SECONDARY_SWAP, SPARK_VALUE);

        CallerAndCommenter callerAndCommenter = new CallerAndCommenter(address(callerAndCommenterImpl));

        CallerAndCommenterImpl(payable(address(callerAndCommenter))).initialize(owner);

        address[] memory delegateCommenters = new address[](1);
        delegateCommenters[0] = address(callerAndCommenter);

        CommentsImpl(payable(address(comments))).initialize(owner, backfiller, delegateCommenters);

        vm.stopBroadcast();

        deployment.comments = address(comments);
        deployment.commentsBlockNumber = block.number;
        deployment.callerAndCommenter = address(callerAndCommenter);
        deployment.callerAndCommenterImpl = address(callerAndCommenterImpl);

        // save the deployment json
        saveDeployment(deployment);

        console.log("Comments deployed at", address(comments));
    }
}
