// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ZoraAccountTestSetup.sol";

contract ZoraAccountTest is ZoraAccountTestSetup {
    ZoraAccountImpl internal account;

    function setUp() public override {
        super.setUp();

        account = deployAccount(accountOwnerEOA, uint256(accountOwnerSalt));
    }

    function testExecuteViaOwner() public {
        vm.prank(accountOwnerEOA);
        account.execute(address(0), 0, "");
    }

    function testExecuteWithValueViaOwner() public {
        address testAddress = makeAddr("test");
        vm.deal(address(account), 1 ether);
        vm.prank(accountOwnerEOA);
        account.execute(testAddress, 1 ether, "");
        assertEq(testAddress.balance, 1 ether);
    }
}
