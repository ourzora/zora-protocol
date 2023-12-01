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

    function testOwner() public {
        bool isOwner = account.isApprovedOwner(accountOwnerEOA);
        assertTrue(isOwner);

        address[] memory owners = account.getOwners();
        assertEq(owners.length, 1);
        assertEq(owners[0], accountOwnerEOA);
    }

    function testExecuteViaOwner() public {
        vm.prank(accountOwnerEOA);
        account.execute(address(mock721), 0, abi.encodeWithSelector(mock721.setSalePrice.selector, 1 ether));

        assertEq(mock721.salePrice(), 1 ether);
    }
}
