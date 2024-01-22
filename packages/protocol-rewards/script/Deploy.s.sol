// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./ScriptBase.sol";
import {stdJson} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {ProtocolRewards} from "../src/ProtocolRewards.sol";

struct DeterministicConfig {
    bytes32 salt;
    bytes creationCode;
    address expectedAddress;
}

contract DeployScript is ScriptBase {
    using stdJson for string;

    function run() public {
        (bytes memory creationCode, bytes32 salt, address expectedAddress) = readDeterministicConfig();
        vm.startBroadcast();

        console2.log("creation code hash");
        bytes32 creationCodeHash = keccak256(creationCode);
        console2.logBytes32(creationCodeHash);

        // Assert to ensure bytecode has not changed
        assert(bytes32(0xfa8c14fa41eb1f11f85062d699fe173e7ae3c1e988f0fa4c1846ac7948b6c471) == creationCodeHash);

        // Sanity check for address
        assert(IMMUTABLE_CREATE2_FACTORY.findCreate2Address(salt, creationCode) == expectedAddress);

        address result = IMMUTABLE_CREATE2_FACTORY.safeCreate2(salt, creationCode);

        console2.log("PROTOCOL REWARDS DEPLOYED:");
        console2.logAddress(address(result));

        vm.stopBroadcast();
    }

    function readDeterministicConfig() internal view returns (bytes memory creationCode, bytes32 salt, address expectedAddress) {
        string memory deployConfig = vm.readFile("deterministicConfig.json");

        creationCode = deployConfig.readBytes(".creationCode");
        expectedAddress = deployConfig.readAddress(".expectedAddress");
        salt = deployConfig.readBytes32(".salt");
    }
}
