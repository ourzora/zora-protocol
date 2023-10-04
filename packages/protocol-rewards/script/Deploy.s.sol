// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./ScriptBase.sol";

import {console2} from "forge-std/console2.sol";

import {ProtocolRewards} from "../src/ProtocolRewards.sol";

contract DeployScript is ScriptBase {
    function run() public {
        vm.startBroadcast(deployer);

        // ProtocolRewards protocolRewards = new ProtocolRewards();

        bytes memory creationCode = type(ProtocolRewards).creationCode;

        bytes32 salt = bytes32(0x0000000000000000000000000000000000000000668d7f9eb18e35000dbaaa0f);

        console2.log("creation code hash");
        bytes32 creationCodeHash = keccak256(creationCode);
        console2.logBytes32(creationCodeHash);

        // Assert to ensure bytecode has not changed
        assert(bytes32(0xfa8c14fa41eb1f11f85062d699fe173e7ae3c1e988f0fa4c1846ac7948b6c471) == creationCodeHash);

        // Sanity check for address
        assert(IMMUTABLE_CREATE2_FACTORY.findCreate2Address(salt, creationCode) == address(0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B));

        address result = IMMUTABLE_CREATE2_FACTORY.safeCreate2(salt, creationCode);

        console2.log("PROTOCOL REWARDS DEPLOYED:");
        console2.logAddress(address(result));

        vm.stopBroadcast();
    }
}
