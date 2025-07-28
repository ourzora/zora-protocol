// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./utils/BaseTest.sol";

contract MultiOwnableTest is BaseTest {
    function setUp() public override {
        super.setUp();

        _deployV4Coin();
    }

    function test_initial_owners() public view {
        assertEq(coinV4.owners().length, 1);
        assertEq(coinV4.owners()[0], users.creator);
        assertEq(coinV4.isOwner(users.creator), true);
    }

    function test_add_owners() public {
        address[] memory newOwners = new address[](2);
        newOwners[0] = makeAddr("NewOwner1");
        newOwners[1] = makeAddr("NewOwner2");

        vm.prank(users.creator);
        coinV4.addOwners(newOwners);

        assertEq(coinV4.owners().length, 3);
        assertEq(coinV4.isOwner(users.creator), true);
        assertEq(coinV4.isOwner(newOwners[0]), true);
        assertEq(coinV4.isOwner(newOwners[1]), true);
    }

    function test_add_owner() public {
        vm.prank(users.creator);
        coinV4.addOwner(address(this));

        assertEq(coinV4.owners().length, 2);
        assertEq(coinV4.isOwner(users.creator), true);
        assertEq(coinV4.isOwner(address(this)), true);
    }

    function test_remove_owners() public {
        address[] memory newOwners = new address[](2);
        newOwners[0] = makeAddr("NewOwner1");
        newOwners[1] = makeAddr("NewOwner2");

        vm.prank(users.creator);
        coinV4.addOwners(newOwners);

        vm.prank(users.creator);
        coinV4.removeOwners(newOwners);

        assertEq(coinV4.owners().length, 1);
        assertEq(coinV4.isOwner(users.creator), true);
        assertEq(coinV4.isOwner(newOwners[0]), false);
        assertEq(coinV4.isOwner(newOwners[1]), false);
    }

    function test_remove_owner() public {
        vm.prank(users.creator);
        coinV4.addOwner(address(this));

        vm.prank(address(this));
        coinV4.removeOwner(users.creator);

        assertEq(coinV4.owners().length, 1);
        assertEq(coinV4.isOwner(users.creator), false);
        assertEq(coinV4.isOwner(address(this)), true);
    }

    function test_revert_only_owner_can_add() public {
        vm.expectRevert(abi.encodeWithSelector(MultiOwnable.OnlyOwner.selector));
        coinV4.addOwner(address(this));
    }

    function test_revert_only_owner_can_remove() public {
        vm.expectRevert(abi.encodeWithSelector(MultiOwnable.OnlyOwner.selector));

        vm.prank(address(this));
        coinV4.removeOwner(users.creator);
    }

    function test_revert_cannot_remove_not_owner() public {
        vm.expectRevert(abi.encodeWithSelector(MultiOwnable.NotOwner.selector));
        vm.prank(users.creator);
        coinV4.removeOwner(address(this));
    }

    function test_revert_last_owner_must_revoke() public {
        address newOwner = makeAddr("NewOwner1");

        vm.prank(users.creator);
        coinV4.addOwner(newOwner);

        vm.prank(newOwner);
        coinV4.removeOwner(users.creator);

        vm.prank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(MultiOwnable.UseRevokeOwnershipToRemoveSelf.selector));
        coinV4.removeOwner(newOwner);
    }

    function test_revoke_ownership() public {
        vm.prank(users.creator);
        coinV4.revokeOwnership();

        assertEq(coinV4.owners().length, 0);
        assertEq(coinV4.isOwner(users.creator), false);
    }

    function test_revert_add_owners_with_zero_address() public {
        address newOwner = makeAddr("NewOwner1");
        address[] memory newOwners = new address[](2);
        newOwners[0] = newOwner;
        newOwners[1] = address(0);

        vm.prank(users.creator);
        vm.expectRevert(MultiOwnable.OwnerCannotBeAddressZero.selector);
        coinV4.addOwners(newOwners);
    }

    function test_revert_add_owners_with_duplicate() public {
        address newOwner = makeAddr("NewOwner1");
        address[] memory newOwners = new address[](2);
        newOwners[0] = newOwner;
        newOwners[1] = newOwner;

        vm.prank(users.creator);
        coinV4.addOwner(newOwner);

        vm.expectRevert(MultiOwnable.AlreadyOwner.selector);
        vm.prank(users.creator);
        coinV4.addOwners(newOwners);
    }

    function test_revert_init_with_zero_owners() public {
        address[] memory emptyOwners = new address[](0);
        bytes memory poolConfig_ = _generatePoolConfig(address(weth));
        vm.expectRevert(MultiOwnable.OneOwnerRequired.selector);
        factory.deploy(users.creator, emptyOwners, "https://test.com", "Test Token", "TEST", poolConfig_, users.platformReferrer, 0);
    }

    function test_revert_init_with_zero_address() public {
        address[] memory owners = new address[](1);
        owners[0] = address(0);
        bytes memory poolConfig_ = _generatePoolConfig(address(weth));
        vm.expectRevert(MultiOwnable.OwnerCannotBeAddressZero.selector);
        factory.deploy(users.creator, owners, "https://test.com", "Test Token", "TEST", poolConfig_, users.platformReferrer, 0);
    }

    function test_revert_init_with_duplicate_owner() public {
        address[] memory owners = new address[](2);
        owners[0] = users.creator;
        owners[1] = users.creator;
        bytes memory poolConfig_ = _generatePoolConfig(address(weth));
        vm.expectRevert(MultiOwnable.AlreadyOwner.selector);
        factory.deploy(users.creator, owners, "https://test.com", "Test Token", "TEST", poolConfig_, users.platformReferrer, 0);
    }
}
