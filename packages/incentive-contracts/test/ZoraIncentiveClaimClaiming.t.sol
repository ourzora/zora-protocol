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

contract ZoraIncentiveClaimClaimingTest is Test {
    ZoraIncentiveClaim public incentive;
    MockERC20 public token;

    address public owner = makeAddr("owner");
    address public allocationSetter = makeAddr("allocationSetter");
    address public kycVerifier = makeAddr("kycVerifier");
    address public fundingWallet = makeAddr("fundingWallet");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public recipient = makeAddr("recipient");

    uint256 private kycVerifierKey;

    function setUp() public {
        // Generate deterministic private key for kycVerifier
        kycVerifierKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
        kycVerifier = vm.addr(kycVerifierKey);

        token = new MockERC20();
        incentive = new ZoraIncentiveClaim(address(token), allocationSetter, kycVerifier, owner, fundingWallet);
    }

    function createAndFundPeriod(uint256 periodId, uint256 allocation1, uint256 allocation2) internal {
        // Create period with allocations
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](2);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: allocation1});
        allocations[1] = IZoraIncentiveClaim.Allocation({user: user2, amount: allocation2});

        incentive.setAllocations(periodId, "Test Period", allocations, block.timestamp + 1, block.timestamp + 30 days);

        // Fund the funding wallet and approve the contract
        uint256 totalFunding = allocation1 + allocation2;
        token.mint(fundingWallet, totalFunding);
        vm.prank(fundingWallet);
        token.approve(address(incentive), totalFunding);

        // Advance time so period has started
        vm.warp(block.timestamp + 2);
    }

    function createAndFundSingleUserPeriod(uint256 periodId, uint256 allocation) internal {
        // Create period with single user allocation
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: allocation});

        incentive.setAllocations(periodId, "Test Period", allocations, block.timestamp + 1, block.timestamp + 30 days);

        // Fund the funding wallet and approve the contract
        token.mint(fundingWallet, allocation);
        vm.prank(fundingWallet);
        token.approve(address(incentive), allocation);

        // Advance time so period has started
        vm.warp(block.timestamp + 2);
    }

    function signClaim(address account, address claimTo, uint256 periodId, uint256 deadline) internal view returns (bytes memory) {
        // Manually construct domain separator to match EIP712 implementation
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

    function testSuccessfulSinglePeriodClaim() public {
        uint256 periodId = 1;
        createAndFundPeriod(periodId, 1000 ether, 2000 ether);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = signClaim(user1, user1, periodId, deadline);

        uint256 balanceBefore = token.balanceOf(user1);

        vm.expectEmit(true, true, false, true);
        emit IZoraIncentiveClaim.Claimed(user1, user1, periodId, 1000 ether);

        incentive.claim(user1, user1, periodId, deadline, signature);

        assertEq(token.balanceOf(user1), balanceBefore + 1000 ether);
        assertTrue(incentive.hasClaimed(periodId, user1));
    }

    function testSuccessfulClaimToDifferentAddress() public {
        uint256 periodId = 1;
        createAndFundPeriod(periodId, 1000 ether, 2000 ether);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = signClaim(user1, recipient, periodId, deadline);

        uint256 balanceBefore = token.balanceOf(recipient);

        vm.expectEmit(true, true, false, true);
        emit IZoraIncentiveClaim.Claimed(user1, recipient, periodId, 1000 ether);

        incentive.claim(user1, recipient, periodId, deadline, signature);

        assertEq(token.balanceOf(recipient), balanceBefore + 1000 ether);
        assertTrue(incentive.hasClaimed(periodId, user1));
    }

    function testMultipleSinglePeriodClaims() public {
        // Create two separate periods and approve total amount upfront
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory allocations1 = new IZoraIncentiveClaim.Allocation[](1);
        allocations1[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});
        incentive.setAllocations(1, "Test Period", allocations1, block.timestamp + 1, block.timestamp + 30 days);

        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory allocations2 = new IZoraIncentiveClaim.Allocation[](1);
        allocations2[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 500 ether});
        incentive.setAllocations(2, "Test Period", allocations2, block.timestamp + 1, block.timestamp + 30 days);

        // Fund and approve total for both periods
        token.mint(fundingWallet, 1500 ether);
        vm.prank(fundingWallet);
        token.approve(address(incentive), 1500 ether);

        // Advance time so periods have started
        vm.warp(block.timestamp + 2);

        uint256 deadline = block.timestamp + 1 hours;

        // Claim from first period
        bytes memory signature1 = signClaim(user1, user1, 1, deadline);
        uint256 balanceBefore = token.balanceOf(user1);

        vm.expectEmit(true, true, false, true);
        emit IZoraIncentiveClaim.Claimed(user1, user1, 1, 1000 ether);
        incentive.claim(user1, user1, 1, deadline, signature1);

        assertEq(token.balanceOf(user1), balanceBefore + 1000 ether);
        assertTrue(incentive.hasClaimed(1, user1));

        // Claim from second period
        bytes memory signature2 = signClaim(user1, user1, 2, deadline);
        balanceBefore = token.balanceOf(user1);

        vm.expectEmit(true, true, false, true);
        emit IZoraIncentiveClaim.Claimed(user1, user1, 2, 500 ether);
        incentive.claim(user1, user1, 2, deadline, signature2);

        assertEq(token.balanceOf(user1), balanceBefore + 500 ether);
        assertTrue(incentive.hasClaimed(2, user1));
    }

    function testInvalidSignatureReverts() public {
        createAndFundPeriod(1, 1000 ether, 2000 ether);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory invalidSignature = hex"deadbeef";

        vm.expectRevert();
        incentive.claim(user1, user1, 1, deadline, invalidSignature);
    }

    function testWrongSignerReverts() public {
        createAndFundPeriod(1, 1000 ether, 2000 ether);

        uint256 deadline = block.timestamp + 1 hours;

        // Sign with wrong private key
        uint256 wrongKey = 0x9999999999999999999999999999999999999999999999999999999999999999;
        address wrongSigner = vm.addr(wrongKey);

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
            abi.encode(keccak256("Claim(address account,address claimTo,uint256 periodId,uint256 deadline)"), user1, user1, 1, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, digest);
        bytes memory wrongSignature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(ZoraIncentiveClaim.InvalidSignature.selector, kycVerifier, wrongSigner));
        incentive.claim(user1, user1, 1, deadline, wrongSignature);
    }

    function testExpiredSignatureReverts() public {
        createAndFundPeriod(1, 1000 ether, 2000 ether);

        uint256 deadline = block.timestamp - 1; // Expired deadline
        bytes memory signature = signClaim(user1, user1, 1, deadline);

        vm.expectRevert(abi.encodeWithSelector(ZoraIncentiveClaim.SignatureExpired.selector, deadline, block.timestamp));
        incentive.claim(user1, user1, 1, deadline, signature);
    }

    function testDoubleClaimReverts() public {
        createAndFundPeriod(1, 1000 ether, 2000 ether);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = signClaim(user1, user1, 1, deadline);

        // First claim should succeed
        incentive.claim(user1, user1, 1, deadline, signature);

        // Second claim should revert with AlreadyClaimed error
        vm.expectRevert(abi.encodeWithSelector(ZoraIncentiveClaim.AlreadyClaimed.selector, user1, 1));
        incentive.claim(user1, user1, 1, deadline, signature);
    }

    function testClaimFromExpiredPeriodReverts() public {
        // Create period that expires soon
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});

        uint256 expiryTime = block.timestamp + 1 hours;
        incentive.setAllocations(1, "Test Period", allocations, block.timestamp + 1, expiryTime);

        // Fund the funding wallet and approve
        token.mint(fundingWallet, 1000 ether);
        vm.prank(fundingWallet);
        token.approve(address(incentive), 1000 ether);

        // Move time forward past expiry
        vm.warp(expiryTime + 1);

        // Create signature with deadline far in the future so signature doesn't expire first
        uint256 deadline = block.timestamp + 1 days;
        bytes memory signature = signClaim(user1, user1, 1, deadline);

        vm.expectRevert(abi.encodeWithSelector(ZoraIncentiveClaim.PeriodExpired.selector, 1, expiryTime));
        incentive.claim(user1, user1, 1, deadline, signature);
    }

    function testClaimWithNoAllocationReverts() public {
        createAndFundPeriod(1, 1000 ether, 2000 ether);

        uint256 deadline = block.timestamp + 1 hours;
        // Sign for user with no allocation
        address userNoAllocation = makeAddr("userNoAllocation");
        bytes memory signature = signClaim(userNoAllocation, userNoAllocation, 1, deadline);

        vm.expectRevert(abi.encodeWithSelector(ZoraIncentiveClaim.NoAllocation.selector, userNoAllocation, 1));
        incentive.claim(userNoAllocation, userNoAllocation, 1, deadline, signature);
    }

    function testClaimFromPeriodNotStartedReverts() public {
        // Create period that starts in the future
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});

        uint256 startTime = block.timestamp + 1 hours; // Starts in 1 hour
        uint256 endTime = block.timestamp + 2 hours;
        incentive.setAllocations(1, "Future Period", allocations, startTime, endTime);

        // Fund the funding wallet and approve
        token.mint(fundingWallet, 1000 ether);
        vm.prank(fundingWallet);
        token.approve(address(incentive), 1000 ether);

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = signClaim(user1, user1, 1, deadline);

        vm.expectRevert(abi.encodeWithSelector(ZoraIncentiveClaim.PeriodNotStarted.selector, 1, startTime));
        incentive.claim(user1, user1, 1, deadline, signature);
    }

    function testClaimFromUnderfundedPeriodReverts() public {
        // Create period with allocation but don't fund the funding wallet enough
        createAndFundSingleUserPeriod(1, 1000 ether);

        // Remove most tokens from funding wallet to simulate underfunding
        vm.prank(fundingWallet);
        token.transfer(makeAddr("somewhere"), 500 ether); // Leave only 500 ether

        uint256 deadline = block.timestamp + 1 hours;
        bytes memory signature = signClaim(user1, user1, 1, deadline);

        // This should revert during the safeTransferFrom when there are insufficient funds
        vm.expectRevert();
        incentive.claim(user1, user1, 1, deadline, signature);
    }
}
