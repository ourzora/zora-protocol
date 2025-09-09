// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ZoraIncentiveClaim} from "../src/ZoraIncentiveClaim.sol";
import {IZoraIncentiveClaim} from "../src/IZoraIncentiveClaim.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract ZoraIncentiveClaimAccessControlTest is Test {
    ZoraIncentiveClaim public incentive;
    MockERC20 public token;

    address public owner = makeAddr("owner");
    address public allocationSetter = makeAddr("allocationSetter");
    address public kycVerifier = makeAddr("kycVerifier");
    address public fundingWallet = makeAddr("fundingWallet");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    function setUp() public {
        token = new MockERC20();
        incentive = new ZoraIncentiveClaim(address(token), allocationSetter, kycVerifier, owner, fundingWallet);
    }

    // Role Getter Tests
    function testRoleGetters() public view {
        ZoraIncentiveClaim.Roles memory roles = incentive.getRoles();
        assertEq(incentive.owner(), owner);
        assertEq(roles.allocationSetter, allocationSetter);
        assertEq(roles.kycVerifier, kycVerifier);
        assertEq(roles.fundingWallet, fundingWallet);
    }

    // setAllocations Access Control Tests
    function testOnlyAllocationSetterCanSetAllocations() public {
        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});

        vm.prank(user1);
        vm.expectRevert(ZoraIncentiveClaim.OnlyAllocationSetter.selector);
        incentive.setAllocations(1, "Period 1", allocations, block.timestamp + 1, block.timestamp + 30 days);
    }

    function testAllocationSetterCanSetAllocations() public {
        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});

        vm.prank(allocationSetter);
        incentive.setAllocations(1, "Test Period", allocations, block.timestamp + 1, block.timestamp + 30 days);

        assertEq(incentive.nextPeriodId(), 2);
    }

    function testAdminCannotSetAllocations() public {
        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});

        vm.prank(owner);
        vm.expectRevert(ZoraIncentiveClaim.OnlyAllocationSetter.selector);
        incentive.setAllocations(1, "Period 1", allocations, block.timestamp + 1, block.timestamp + 30 days);
    }

    // setRoles Access Control Tests
    function testOnlyAdminCanSetRoles() public {
        address newAllocationSetter = makeAddr("newAllocationSetter");
        address newKycVerifier = makeAddr("newKycVerifier");
        address newFundingWallet = makeAddr("newFundingWallet");

        vm.prank(user1);
        vm.expectRevert();
        incentive.setRoles(newAllocationSetter, newKycVerifier, newFundingWallet);
    }

    function testAdminCanSetRoles() public {
        address newAllocationSetter = makeAddr("newAllocationSetter");
        address newKycVerifier = makeAddr("newKycVerifier");
        address newFundingWallet = makeAddr("newFundingWallet");

        vm.prank(owner);
        incentive.setRoles(newAllocationSetter, newKycVerifier, newFundingWallet);

        ZoraIncentiveClaim.Roles memory roles = incentive.getRoles();

        assertEq(incentive.owner(), owner);
        assertEq(roles.allocationSetter, newAllocationSetter);
        assertEq(roles.kycVerifier, newKycVerifier);
        assertEq(roles.fundingWallet, newFundingWallet);
    }

    function testAllocationSetterCannotSetRoles() public {
        address newAllocationSetter = makeAddr("newAllocationSetter");
        address newKycVerifier = makeAddr("newKycVerifier");
        address newFundingWallet = makeAddr("newFundingWallet");

        vm.prank(allocationSetter);
        vm.expectRevert();
        incentive.setRoles(newAllocationSetter, newKycVerifier, newFundingWallet);
    }

    // updateAllocations Access Control Tests
    function testOnlyAllocationSetterCanUpdateAllocations() public {
        // First create a period
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});
        incentive.setAllocations(1, "Test Period", allocations, block.timestamp + 1, block.timestamp + 30 days);

        // Try to update as non-allocation-setter
        IZoraIncentiveClaim.Allocation[] memory newAllocations = new IZoraIncentiveClaim.Allocation[](1);
        newAllocations[0] = IZoraIncentiveClaim.Allocation({user: user2, amount: 2000 ether});

        vm.prank(user1);
        vm.expectRevert(ZoraIncentiveClaim.OnlyAllocationSetter.selector);
        incentive.updateAllocations(1, newAllocations);
    }

    function testAllocationSetterCanUpdateAllocations() public {
        // First create a period that starts in the future
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});
        incentive.setAllocations(1, "Test Period", allocations, block.timestamp + 1 hours, block.timestamp + 30 days);

        // Update as allocation setter should work
        IZoraIncentiveClaim.Allocation[] memory newAllocations = new IZoraIncentiveClaim.Allocation[](1);
        newAllocations[0] = IZoraIncentiveClaim.Allocation({user: user2, amount: 2000 ether});

        vm.prank(allocationSetter);
        incentive.updateAllocations(1, newAllocations);

        assertEq(incentive.periodAllocations(1, user2), 2000 ether);
    }

    function testAdminCannotUpdateAllocations() public {
        // First create a period
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});
        incentive.setAllocations(1, "Test Period", allocations, block.timestamp + 1, block.timestamp + 30 days);

        // Try to update as admin
        IZoraIncentiveClaim.Allocation[] memory newAllocations = new IZoraIncentiveClaim.Allocation[](1);
        newAllocations[0] = IZoraIncentiveClaim.Allocation({user: user2, amount: 2000 ether});

        vm.prank(owner);
        vm.expectRevert(ZoraIncentiveClaim.OnlyAllocationSetter.selector);
        incentive.updateAllocations(1, newAllocations);
    }

    // Cross-role validation tests
    function testRoleSeparation() public {
        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});

        // Only allocation setter can set allocations
        vm.prank(owner);
        vm.expectRevert(ZoraIncentiveClaim.OnlyAllocationSetter.selector);
        incentive.setAllocations(1, "Period 1", allocations, block.timestamp + 1, block.timestamp + 30 days);

        vm.prank(kycVerifier);
        vm.expectRevert(ZoraIncentiveClaim.OnlyAllocationSetter.selector);
        incentive.setAllocations(1, "Period 1", allocations, block.timestamp + 1, block.timestamp + 30 days);

        // Create a period properly
        vm.prank(allocationSetter);
        incentive.setAllocations(1, "Test Period", allocations, block.timestamp + 1, block.timestamp + 30 days);

        // Only owner can set roles
        address newAllocationSetter = makeAddr("newAllocationSetter");
        address newKycVerifier = makeAddr("newKycVerifier");
        address newFundingWallet = makeAddr("newFundingWallet");

        vm.prank(allocationSetter);
        vm.expectRevert(); // Ownable2Step throws OwnableUnauthorizedAccount
        incentive.setRoles(newAllocationSetter, newKycVerifier, newFundingWallet);

        vm.prank(kycVerifier);
        vm.expectRevert(); // Ownable2Step throws OwnableUnauthorizedAccount
        incentive.setRoles(newAllocationSetter, newKycVerifier, newFundingWallet);
    }

    // updateAllocations with invalid period ID tests
    function testUpdateNonExistentPeriodReverts() public {
        uint256 nonExistentPeriodId = 999;
        IZoraIncentiveClaim.Allocation[] memory newAllocations = new IZoraIncentiveClaim.Allocation[](1);
        newAllocations[0] = IZoraIncentiveClaim.Allocation({user: user2, amount: 2000 ether});

        vm.prank(allocationSetter);
        vm.expectRevert(abi.encodeWithSelector(ZoraIncentiveClaim.PeriodDoesNotExist.selector, nonExistentPeriodId));
        incentive.updateAllocations(nonExistentPeriodId, newAllocations);
    }

    // setRoles validation tests
    function testSetRolesWithZeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert(ZoraIncentiveClaim.ZeroAddress.selector);
        incentive.setRoles(address(0), kycVerifier, fundingWallet);

        vm.prank(owner);
        vm.expectRevert(ZoraIncentiveClaim.ZeroAddress.selector);
        incentive.setRoles(allocationSetter, address(0), fundingWallet);

        vm.prank(owner);
        vm.expectRevert(ZoraIncentiveClaim.ZeroAddress.selector);
        incentive.setRoles(allocationSetter, kycVerifier, address(0));
    }

    // Period validation tests
    function testSetAllocationsWithInvalidPeriodIdReverts() public {
        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});

        vm.prank(allocationSetter);
        vm.expectRevert(ZoraIncentiveClaim.InvalidPeriodId.selector);
        incentive.setAllocations(2, "Period 2", allocations, block.timestamp + 1, block.timestamp + 30 days); // Should be 1
    }
}
