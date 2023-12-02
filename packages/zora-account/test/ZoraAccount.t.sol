// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ZoraAccountTestSetup.sol";

import "./utils/MockNFTs.sol";

contract ZoraAccountTest is ZoraAccountTestSetup {
    ZoraAccountImpl internal account;

    MockERC721 internal mock721;
    MockERC1155 internal mock1155;

    function setUp() public override {
        super.setUp();

        account = deployAccount(accountOwnerEOA, uint256(accountOwnerSalt));

        mock721 = new MockERC721(address(account));
        mock1155 = new MockERC1155(address(account));
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
