// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import {ZoraCreatorRedeemMinterFactory} from "../src/minters/redeem/ZoraCreatorRedeemMinterFactory.sol";

contract DeployScript is Script {
    function run() public {
        address deployer = vm.envAddress("DEPLOYER");
        vm.startBroadcast(deployer);

        ZoraCreatorRedeemMinterFactory minterFactory = new ZoraCreatorRedeemMinterFactory();

        vm.stopBroadcast();
    }
}
