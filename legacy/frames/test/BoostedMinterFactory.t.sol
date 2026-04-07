// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {BoostedMinterFactory} from "../src/BoostedMinterFactory.sol";
import {BoostedMinterFactoryImpl} from "../src/BoostedMinterFactoryImpl.sol";
import {BoostedMinterImpl} from "../src/BoostedMinterImpl.sol";

import {Zora1155Test} from "./Zora1155Test.sol";

contract BoostedMinterFactoryTest is Zora1155Test {
    address internal owner;
    BoostedMinterFactoryImpl internal factory;

    function setUp() public override {
        super.setUp();

        owner = makeAddr("owner");
        BoostedMinterFactoryImpl factoryImpl = new BoostedMinterFactoryImpl();
        address proxy = address(
            new BoostedMinterFactory(
                address(factoryImpl), abi.encodeWithSelector(BoostedMinterFactoryImpl.initialize.selector, owner)
            )
        );
        factory = BoostedMinterFactoryImpl(proxy);
    }

    function testOwner() public {
        assertEq(factory.owner(), owner);
    }

    function testDeployBoostedMinter() public {
        address minter = factory.deployBoostedMinter(address(zora1155), zora1155TokenId);
        assertEq(factory.boostedMinterForCollection(address(zora1155), zora1155TokenId), minter);
    }
}
