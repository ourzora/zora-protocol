// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraCreatorRedeemMinterFactoryImpl} from "../src/minters/redeem/ZoraCreatorRedeemMinterFactoryImpl.sol";
import {ZoraRedeemMinterFactory} from "../src/proxies/ZoraRedeemMinterFactory.sol";

contract DeployScript is Script {
    function run() public {
        address key = vm.envAddress("DEPLOYER");
        vm.startBroadcast(key);

        // TODO: use a static contract for the factory
        ZoraCreatorRedeemMinterFactoryImpl minterFactoryImpl = new ZoraCreatorRedeemMinterFactoryImpl();
        ZoraRedeemMinterFactory minterFactoryProxy = new ZoraRedeemMinterFactory(address(minterFactoryImpl), "");
        ZoraCreatorRedeemMinterFactoryImpl(address(minterFactoryProxy)).initialize(key);

        vm.stopBroadcast();
    }
}
