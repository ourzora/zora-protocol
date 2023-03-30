// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import {ZoraCreatorRedeemMinterFactoryImpl} from "../src/minters/redeem/ZoraCreatorRedeemMinterFactoryImpl.sol";

contract DeployScript is Script {
    function run() public {
        address deployer = vm.envAddress("DEPLOYER");
        vm.startBroadcast(deployer);

        ZoraCreatorRedeemMinterFactoryImpl minterFactoryProxy = new ZoraCreatorRedeemMinterFactoryImpl();
        minterFactoryProxy.initialize(deployer);

        vm.stopBroadcast();
    }
}
