// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraCreatorRedeemMinterFactoryImpl} from "../src/minters/redeem/ZoraCreatorRedeemMinterFactoryImpl.sol";
import {ZoraRedeemMinterFactory} from "../src/proxies/ZoraRedeemMinterFactory.sol";

contract DeployScript is Script {
    function run() public {
        uint256 key = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(key);

        ZoraCreatorRedeemMinterFactoryImpl minterFactoryImpl = new ZoraCreatorRedeemMinterFactoryImpl();
        ZoraRedeemMinterFactory minterFactoryProxy = new ZoraRedeemMinterFactory(address(minterFactoryImpl), "");

        vm.stopBroadcast();
    }
}
