// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {MultichainScript} from "./MultichainScript.sol";
import {BoostedMinterImpl} from "../src/BoostedMinterImpl.sol";
import {BoostedMinterFactoryImpl} from "../src/BoostedMinterFactoryImpl.sol";
import {BoostedMinterFactory} from "../src/BoostedMinterFactory.sol";

contract Deploy is MultichainScript {
    function runForChain() public override {
        address owner = vm.parseJsonAddress(chainConfig(), "OWNER");
        address proxy = vm.parseJsonAddress(addresses(), "BOOSTED_MINTER_FACTORY_PROXY");

        console2.log("UPGRADING BOOSTED MINTER FACTORY:", proxy);

        BoostedMinterFactoryImpl factoryImpl = new BoostedMinterFactoryImpl();

        console2.log("FACTORY IMPL:", address(factoryImpl));
        BoostedMinterFactoryImpl factory = BoostedMinterFactoryImpl(proxy);

        factory.upgradeTo(address(factoryImpl));
        console2.log("MINTER IMPL:", address(factory.boostedMinterImpl()));

        console2.log("FACTORY OWNER:", factory.owner());
    }
}
