// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {SimpleAA} from "../src/deployment/SimpleAA.sol";

contract DeployMockAA is Script {
    function run() public {
        (address owner, uint256 privateKey) = makeAddrAndKey("owner");

        vm.startBroadcast();

        address aaAddress = address(new SimpleAA(owner));

        vm.stopBroadcast();

        console2.log("AA Address:", aaAddress);
        console2.log("Owner:", owner);
        console2.log("Owner private key:", vm.toString(abi.encode(privateKey)));
    }
}
