// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ZoraAccountTestSetup.sol";

contract ZoraAccountTest is ZoraAccountTestSetup {
    function setUp() public override {
        super.setUp();
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

    function testOwner() public {
        bool isOwner = account.isApprovedOwner(accountOwnerEOA);
        assertTrue(isOwner);

        address[] memory owners = account.getOwners();
        assertEq(owners.length, 1);
        assertEq(owners[0], accountOwnerEOA);
    }

    function testExecuteOwnerSetSale() public {
        vm.prank(accountOwnerEOA);
        account.execute(address(mock721), 0, abi.encodeWithSelector(mock721.setSalePrice.selector, 1 ether));

        assertEq(mock721.salePrice(), 1 ether);
    }

    function testExecuteOwnerMint() public {
        vm.deal(address(account), 1 ether);

        vm.prank(accountOwnerEOA);
        account.execute(address(mock721), 0, abi.encodeWithSelector(mock721.setSalePrice.selector, 1 ether));

        vm.prank(accountOwnerEOA);
        account.execute(address(mock721), 1 ether, abi.encodeWithSelector(mock721.mintWithRewards.selector, address(account), 1));

        assertEq(mock721.ownerOf(0), address(account));
        assertEq(address(mock721).balance, 1 ether);
    }

    function testExecuteViaEntryPointWithAccountEOAOwner() public {
        vm.deal(address(account), 1 ether);

        bytes memory userOpCalldata = getUserOpCalldata(address(mock1155), 0, abi.encodeWithSelector(mock1155.setSalePrice.selector, 1 ether));
        UserOperation memory userOp = getSignedUserOp(accountOwnerPK, address(account), userOpCalldata);

        UserOperation[] memory userOps = new UserOperation[](1);
        userOps[0] = userOp;

        entryPoint.handleOps(userOps, payable(beneficiary));

        assertEq(mock1155.salePrice(), 1 ether);
    }

    function testExecuteViaEntryPointWithAccountContractOwner() public {}

    function testRevertUserOpsWithInvalidSignature() public {}

    function testRevertCannotExecuteIfNotOwner() public {}

    function testRevertDataIs() public {}
}
