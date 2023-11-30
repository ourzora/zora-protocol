// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ZoraAccountTestSetup.sol";

contract ZoraAccountTest is ZoraAccountTestSetup {
    ZoraAccountImpl internal account;

    function setUp() public override {
        super.setUp();

        account = deployAccount(accountOwnerEOA, uint256(accountOwnerSalt));
    }

    function testExecuteViaOwner() public {}

    function testExecuteWithValueViaOwner() public {}
}
