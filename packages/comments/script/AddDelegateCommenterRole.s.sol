// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import {CommentsDeployerBase} from "./CommentsDeployerBase.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract AddDelegateCommenterRole is CommentsDeployerBase {
    function run() public view {
        address owner = getProxyAdmin();
        bytes32 BACKFILLER_ROLE = keccak256("DELEGATE_COMMENTER");

        address callerAndCommenter = readDeterministicContractConfig("callerAndCommenter").deployedAddress;

        address comments = readDeterministicContractConfig("comments").deployedAddress;

        bytes memory call = abi.encodeWithSelector(AccessControlUpgradeable.grantRole.selector, BACKFILLER_ROLE, callerAndCommenter);

        console.log("multisig", owner);
        console.log("target", comments);
        console.log("call:");
        console.logBytes(call);
    }
}
