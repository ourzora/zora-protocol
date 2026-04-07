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

        address factoryImpl = address(new BoostedMinterFactoryImpl());

        address factoryProxy = address(
            new BoostedMinterFactory(
                factoryImpl, abi.encodeWithSelector(BoostedMinterFactoryImpl.initialize.selector, owner)
            )
        );
        console2.log("FACTORY PROXY:", address(BoostedMinterFactoryImpl(factoryProxy).boostedMinterImpl()));
        console2.log("FACTORY IMPL:", address(factoryImpl));

        console2.log("MINTER IMPL:", address(BoostedMinterFactoryImpl(factoryProxy).boostedMinterImpl()));

        console2.log("FACTORY OWNER:", BoostedMinterFactoryImpl(factoryProxy).owner());
    }
}
