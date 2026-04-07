// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {BoostedMinterFactory} from "../src/BoostedMinterFactory.sol";
import {BoostedMinterFactoryImpl} from "../src/BoostedMinterFactoryImpl.sol";
import {BoostedMinterImpl} from "../src/BoostedMinterImpl.sol";
import {Zora1155Test} from "./Zora1155Test.sol";
import {IZoraCreator1155} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155.sol";

contract BoostedMinterTest is Zora1155Test {
    address internal owner;
    address internal recipient;

    BoostedMinterFactoryImpl internal factory;
    BoostedMinterImpl internal minter;
    IZoraCreator1155 internal tokenContract;
    address internal tokenAdmin;

    function setUp() public override {
        super.setUp();

        owner = makeAddr("owner");
        recipient = makeAddr("recipient");

        tokenContract = IZoraCreator1155(address(zora1155));
        tokenAdmin = zora1155.owner();

        BoostedMinterFactoryImpl factoryImpl = new BoostedMinterFactoryImpl();
        address proxy = address(
            new BoostedMinterFactory(
                address(factoryImpl), abi.encodeWithSelector(BoostedMinterFactoryImpl.initialize.selector, owner)
            )
        );
        factory = BoostedMinterFactoryImpl(proxy);
        minter = BoostedMinterImpl(payable(factory.deployBoostedMinter(address(tokenContract), 1)));
    }

    function testDeposit() public {
        (address(minter)).call{value: 1 ether}("");
        assertEq(address(minter).balance, 1 ether);
    }

    function testWithdrawGas() public {
        (address(minter)).call{value: 1 ether}("");

        uint256 balanceBefore = address(minter).balance;

        vm.prank(tokenAdmin);
        minter.withdrawGas(payable(owner), 0.5 ether);

        uint256 balanceAfter = address(minter).balance;

        assertEq(balanceAfter, balanceBefore - 0.5 ether);
        assertEq(owner.balance, 0.5 ether);
    }

    function testMint() public {
        console2.log("minter", address(minter));

        uint256 minterBit = tokenContract.PERMISSION_BIT_MINTER();
        vm.prank(tokenAdmin);
        tokenContract.addPermission(1, address(minter), minterBit);

        uint256 beforeBalance = owner.balance;

        vm.deal(address(minter), 1 ether);

        vm.prank(owner);
        minter.mint(recipient, 1);

        assertEq(tokenContract.balanceOf(recipient, 1), 1);
        assertGe(owner.balance - beforeBalance, 0.00001 ether);
    }

    function testMintRevertNoPermission() public {
        vm.expectRevert();
        vm.prank(owner);
        minter.mint(recipient, 1);
    }

    function testMintRevertOnlyowner() public {
        vm.expectRevert();
        minter.mint(recipient, 1);
    }
}
