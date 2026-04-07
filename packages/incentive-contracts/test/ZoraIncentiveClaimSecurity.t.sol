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

contract ZoraIncentiveClaimSecurityTest is Test {
    ZoraIncentiveClaim public incentive;
    MockERC20 public token;

    address public owner = makeAddr("owner");
    address public allocationSetter = makeAddr("allocationSetter");
    address public kycVerifier = makeAddr("kycVerifier");
    address public fundingWallet = makeAddr("fundingWallet");
    address public user1 = makeAddr("user1");
    address public newOwner = makeAddr("newOwner");
    address public newSetter = makeAddr("newSetter");
    address public newVerifier = makeAddr("newVerifier");
    address public newFundingWallet = makeAddr("newFundingWallet");

    uint256 private kycVerifierKey = 0x1234567890123456789012345678901234567890123456789012345678901234;

    function setUp() public {
        token = new MockERC20();
        kycVerifier = vm.addr(kycVerifierKey);
        incentive = new ZoraIncentiveClaim(address(token), allocationSetter, kycVerifier, owner, fundingWallet);
    }

    // Constructor validation tests
    function testConstructorZeroTokenReverts() public {
        vm.expectRevert(ZoraIncentiveClaim.ZeroAddress.selector);
        new ZoraIncentiveClaim(address(0), allocationSetter, kycVerifier, owner, fundingWallet);
    }

    function testConstructorZeroAllocationSetterReverts() public {
        vm.expectRevert(ZoraIncentiveClaim.ZeroAddress.selector);
        new ZoraIncentiveClaim(address(token), address(0), kycVerifier, owner, fundingWallet);
    }

    function testConstructorZeroKycVerifierReverts() public {
        vm.expectRevert(ZoraIncentiveClaim.ZeroAddress.selector);
        new ZoraIncentiveClaim(address(token), allocationSetter, address(0), owner, fundingWallet);
    }

    function testConstructorZeroOwnerReverts() public {
        vm.expectRevert(); // OpenZeppelin Ownable throws OwnableInvalidOwner for zero address
        new ZoraIncentiveClaim(address(token), allocationSetter, kycVerifier, address(0), fundingWallet);
    }

    function testConstructorZeroFundingWalletReverts() public {
        vm.expectRevert(ZoraIncentiveClaim.ZeroAddress.selector);
        new ZoraIncentiveClaim(address(token), allocationSetter, kycVerifier, owner, address(0));
    }

    // Role management tests
    function testSetRolesSuccess() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit IZoraIncentiveClaim.RolesUpdated(newSetter, newVerifier, newFundingWallet); // Owner managed separately

        incentive.setRoles(newSetter, newVerifier, newFundingWallet);

        ZoraIncentiveClaim.Roles memory roles = incentive.getRoles();
        assertEq(incentive.owner(), owner); // Owner unchanged (managed by Ownable2Step)
        assertEq(roles.allocationSetter, newSetter);
        assertEq(roles.kycVerifier, newVerifier);
        assertEq(roles.fundingWallet, newFundingWallet);
    }

    function testSetRolesOnlyAdmin() public {
        vm.prank(user1);
        vm.expectRevert(); // Ownable2Step throws OwnableUnauthorizedAccount
        incentive.setRoles(newSetter, newVerifier, newFundingWallet);
    }

    function testSetRolesZeroAllocationSetterReverts() public {
        vm.prank(owner);
        vm.expectRevert(ZoraIncentiveClaim.ZeroAddress.selector);
        incentive.setRoles(address(0), newVerifier, newFundingWallet);
    }

    function testSetRolesZeroKycVerifierReverts() public {
        vm.prank(owner);
        vm.expectRevert(ZoraIncentiveClaim.ZeroAddress.selector);
        incentive.setRoles(newSetter, address(0), newFundingWallet);
    }

    function testSetRolesZeroFundingWalletReverts() public {
        vm.prank(owner);
        vm.expectRevert(ZoraIncentiveClaim.ZeroAddress.selector);
        incentive.setRoles(newSetter, newVerifier, address(0));
    }

    // Two-step ownership transfer tests
    function testTwoStepOwnershipTransfer() public {
        address proposedOwner = makeAddr("proposedOwner");

        // Step 1: Current owner proposes transfer
        vm.prank(owner);
        incentive.transferOwnership(proposedOwner);

        // Ownership hasn't changed yet
        assertEq(incentive.owner(), owner);
        assertEq(incentive.pendingOwner(), proposedOwner);

        // Step 2: New owner accepts ownership
        vm.prank(proposedOwner);
        incentive.acceptOwnership();

        // Now ownership has transferred
        assertEq(incentive.owner(), proposedOwner);
        assertEq(incentive.pendingOwner(), address(0));
    }

    function testOnlyPendingOwnerCanAccept() public {
        address proposedOwner = makeAddr("proposedOwner");
        address otherUser = makeAddr("otherUser");

        // Step 1: Propose transfer
        vm.prank(owner);
        incentive.transferOwnership(proposedOwner);

        // Step 2: Wrong user tries to accept
        vm.prank(otherUser);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        incentive.acceptOwnership();

        // Ownership hasn't changed
        assertEq(incentive.owner(), owner);
        assertEq(incentive.pendingOwner(), proposedOwner);
    }

    // Single period claim functionality test
    function testSinglePeriodClaimSuccess() public {
        // Create and fund period
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});
        incentive.setAllocations(1, "Test Period", allocations, block.timestamp + 1, block.timestamp + 30 days);

        // Fund the funding wallet and approve
        token.mint(fundingWallet, 1000 ether);
        vm.prank(fundingWallet);
        token.approve(address(incentive), 1000 ether);

        // Advance time so period has started
        vm.warp(block.timestamp + 2);

        uint256 deadline = block.timestamp + 1 hours;

        // Sign and claim
        bytes memory signature = signClaim(user1, user1, 1, deadline);

        uint256 balanceBefore = token.balanceOf(user1);
        incentive.claim(user1, user1, 1, deadline, signature);

        // Verify claim succeeded
        assertEq(token.balanceOf(user1), balanceBefore + 1000 ether);
        assertTrue(incentive.hasClaimed(1, user1));
    }

    function testDoubleClaimPrevented() public {
        // Create and fund period
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});
        incentive.setAllocations(1, "Test Period", allocations, block.timestamp + 1, block.timestamp + 30 days);

        // Fund the funding wallet and approve
        token.mint(fundingWallet, 1000 ether);
        vm.prank(fundingWallet);
        token.approve(address(incentive), 1000 ether);

        // Advance time so period has started
        vm.warp(block.timestamp + 2);

        uint256 deadline = block.timestamp + 1 hours;

        // Create signature for claim
        bytes memory signature = signClaim(user1, user1, 1, deadline);

        // First claim should succeed
        incentive.claim(user1, user1, 1, deadline, signature);
        assertTrue(incentive.hasClaimed(1, user1));

        // Try to claim again - should fail with AlreadyClaimed
        vm.expectRevert(abi.encodeWithSelector(ZoraIncentiveClaim.AlreadyClaimed.selector, user1, 1));
        incentive.claim(user1, user1, 1, deadline, signature);
    }

    function testClaimFromExpiredPeriodPrevented() public {
        // Create period that will expire
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});
        uint256 expiryTime = block.timestamp + 1 hours;
        incentive.setAllocations(1, "Test Period", allocations, block.timestamp + 1, expiryTime);

        // Fund the funding wallet and approve
        token.mint(fundingWallet, 1000 ether);
        vm.prank(fundingWallet);
        token.approve(address(incentive), 1000 ether);

        // Move time past expiry
        vm.warp(expiryTime + 1);

        // Set deadline far in future so signature doesn't expire first
        uint256 deadline = block.timestamp + 1 days;
        bytes memory signature = signClaim(user1, user1, 1, deadline);

        // Should fail with PeriodExpired
        vm.expectRevert(abi.encodeWithSelector(ZoraIncentiveClaim.PeriodExpired.selector, 1, expiryTime));
        incentive.claim(user1, user1, 1, deadline, signature);
    }

    function testUpdateAllocationsAccessControl() public {
        // First create a period that starts in the future
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});
        incentive.setAllocations(1, "Test Period", allocations, block.timestamp + 1 hours, block.timestamp + 30 days);

        // Try to update as non-allocation-setter
        IZoraIncentiveClaim.Allocation[] memory newAllocations = new IZoraIncentiveClaim.Allocation[](1);
        newAllocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 2000 ether});

        vm.prank(user1);
        vm.expectRevert(ZoraIncentiveClaim.OnlyAllocationSetter.selector);
        incentive.updateAllocations(1, newAllocations);

        // Should work as allocation setter
        vm.prank(allocationSetter);
        incentive.updateAllocations(1, newAllocations);

        assertEq(incentive.periodAllocations(1, user1), 2000 ether);
    }

    function signClaim(address account, address claimTo, uint256 periodId, uint256 deadline) internal view returns (bytes memory) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("ZoraIncentiveClaim"),
                keccak256("0.1.0"),
                block.chainid,
                address(incentive)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(keccak256("Claim(address account,address claimTo,uint256 periodId,uint256 deadline)"), account, claimTo, periodId, deadline)
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(kycVerifierKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
