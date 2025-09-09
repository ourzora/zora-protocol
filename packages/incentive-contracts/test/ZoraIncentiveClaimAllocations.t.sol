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

contract ZoraIncentiveClaimAllocationsTest is Test {
    ZoraIncentiveClaim public incentive;
    MockERC20 public token;

    address public owner = makeAddr("owner");
    address public allocationSetter = makeAddr("allocationSetter");
    address public kycVerifier = makeAddr("kycVerifier");
    address public fundingWallet = makeAddr("fundingWallet");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    function setUp() public {
        token = new MockERC20();
        incentive = new ZoraIncentiveClaim(address(token), allocationSetter, kycVerifier, owner, fundingWallet);
    }

    function testBasicAllocationSetting() public {
        vm.prank(allocationSetter);

        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](2);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});
        allocations[1] = IZoraIncentiveClaim.Allocation({user: user2, amount: 2000 ether});

        uint256 startTime = block.timestamp + 1;
        uint256 expiryDate = block.timestamp + 30 days;

        vm.expectEmit(true, false, false, true);
        emit IZoraIncentiveClaim.AllocationsSet(1, "Test Period 1", allocations, startTime, expiryDate);

        incentive.setAllocations(1, "Test Period 1", allocations, startTime, expiryDate);

        assertEq(incentive.nextPeriodId(), 2);
        assertEq(incentive.periodLabels(1), "Test Period 1");
        assertEq(incentive.periodAllocations(1, user1), 1000 ether);
        assertEq(incentive.periodAllocations(1, user2), 2000 ether);
        assertEq(incentive.periodExpiry(1), expiryDate);
    }

    function testMultiplePeriods() public {
        vm.startPrank(allocationSetter);

        // First period
        IZoraIncentiveClaim.Allocation[] memory allocations1 = new IZoraIncentiveClaim.Allocation[](1);
        allocations1[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});
        incentive.setAllocations(1, "Q1 Rewards", allocations1, block.timestamp + 1, block.timestamp + 30 days);

        // Second period
        IZoraIncentiveClaim.Allocation[] memory allocations2 = new IZoraIncentiveClaim.Allocation[](1);
        allocations2[0] = IZoraIncentiveClaim.Allocation({user: user2, amount: 500 ether});
        incentive.setAllocations(2, "Q2 Rewards", allocations2, block.timestamp + 1, block.timestamp + 60 days);

        vm.stopPrank();

        assertEq(incentive.nextPeriodId(), 3);

        // Verify period isolation
        assertEq(incentive.periodAllocations(1, user1), 1000 ether);
        assertEq(incentive.periodAllocations(1, user2), 0);
        assertEq(incentive.periodAllocations(2, user1), 0);
        assertEq(incentive.periodAllocations(2, user2), 500 ether);
    }

    function testLargeAllocationSet() public {
        vm.prank(allocationSetter);

        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](100);
        for (uint256 i = 0; i < 100; i++) {
            address user = address(uint160(1000 + i));
            uint256 amount = (i + 1) * 100 ether; // Varying amounts
            allocations[i] = IZoraIncentiveClaim.Allocation({user: user, amount: amount});
        }

        incentive.setAllocations(1, "Large Distribution", allocations, block.timestamp + 1, block.timestamp + 30 days);

        // Spot check a few allocations
        assertEq(incentive.periodAllocations(1, address(uint160(1000))), 100 ether);
        assertEq(incentive.periodAllocations(1, address(uint160(1050))), 5100 ether);
        assertEq(incentive.periodAllocations(1, address(uint160(1099))), 10000 ether);
    }

    function testZeroAmountAllowed() public {
        vm.prank(allocationSetter);

        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 0}); // Zero amount now allowed

        incentive.setAllocations(1, "Zero Amount", allocations, block.timestamp + 1, block.timestamp + 30 days);

        // Verify zero allocation was set
        assertEq(incentive.periodAllocations(1, user1), 0);
    }

    function testMaxAmountAllocation() public {
        vm.prank(allocationSetter);

        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        uint256 maxAmount = type(uint256).max; // Now we can use full uint256
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: maxAmount});

        incentive.setAllocations(1, "Max Amount", allocations, block.timestamp + 1, block.timestamp + 30 days);

        assertEq(incentive.periodAllocations(1, user1), maxAmount);
    }

    function testSameUserMultiplePeriods() public {
        vm.startPrank(allocationSetter);

        // Period 1
        IZoraIncentiveClaim.Allocation[] memory allocations1 = new IZoraIncentiveClaim.Allocation[](1);
        allocations1[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});
        incentive.setAllocations(1, "Period 1", allocations1, block.timestamp + 1, block.timestamp + 30 days);

        // Period 2 - same user, different amount
        IZoraIncentiveClaim.Allocation[] memory allocations2 = new IZoraIncentiveClaim.Allocation[](1);
        allocations2[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 500 ether});
        incentive.setAllocations(2, "Period 2", allocations2, block.timestamp + 1, block.timestamp + 60 days);

        vm.stopPrank();

        // User should have different allocations in each period
        assertEq(incentive.periodAllocations(1, user1), 1000 ether);
        assertEq(incentive.periodAllocations(2, user1), 500 ether);
    }

    function testDuplicateUserInSamePeriod() public {
        vm.prank(allocationSetter);

        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](3);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});
        allocations[1] = IZoraIncentiveClaim.Allocation({user: user2, amount: 500 ether});
        allocations[2] = IZoraIncentiveClaim.Allocation({user: user1, amount: 2000 ether}); // Duplicate user1

        incentive.setAllocations(1, "Duplicate Test", allocations, block.timestamp + 1, block.timestamp + 30 days);

        // Last allocation should overwrite the first
        assertEq(incentive.periodAllocations(1, user1), 2000 ether);
        assertEq(incentive.periodAllocations(1, user2), 500 ether);
    }

    function testEmptyAllocations() public {
        vm.prank(allocationSetter);

        IZoraIncentiveClaim.Allocation[] memory emptyAllocations = new IZoraIncentiveClaim.Allocation[](0);

        incentive.setAllocations(1, "Empty Period", emptyAllocations, block.timestamp + 1, block.timestamp + 30 days);

        assertEq(incentive.periodLabels(1), "Empty Period");
        // No allocations should exist
        assertEq(incentive.periodAllocations(1, user1), 0);
    }

    function testStartTimeInPast() public {
        // Warp to a specific time to avoid underflow
        vm.warp(1000000); // Set to a large enough timestamp

        vm.prank(allocationSetter);

        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});

        // Set start time in past to test StartTimeInPast validation
        uint256 pastStartTime = block.timestamp - 1800; // 30 minutes ago
        uint256 futureExpiry = block.timestamp + 30 days; // Future expiry

        vm.expectRevert(ZoraIncentiveClaim.StartTimeInPast.selector);
        incentive.setAllocations(1, "Past Start Time", allocations, pastStartTime, futureExpiry);
    }

    function testExpiryDateFarFuture() public {
        vm.prank(allocationSetter);

        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});

        // Set expiry very far in the future
        uint256 farFutureExpiry = block.timestamp + 365 days * 10; // 10 years

        incentive.setAllocations(1, "Far Future", allocations, block.timestamp + 1, farFutureExpiry);

        assertEq(incentive.periodExpiry(1), farFutureExpiry);
    }

    function testPeriodIdAutoIncrement() public {
        vm.startPrank(allocationSetter);

        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});

        assertEq(incentive.nextPeriodId(), 1);

        incentive.setAllocations(1, "Period 1", allocations, block.timestamp + 1, block.timestamp + 30 days);
        assertEq(incentive.nextPeriodId(), 2);

        incentive.setAllocations(2, "Period 2", allocations, block.timestamp + 1, block.timestamp + 30 days);
        assertEq(incentive.nextPeriodId(), 3);

        incentive.setAllocations(3, "Period 3", allocations, block.timestamp + 1, block.timestamp + 30 days);
        assertEq(incentive.nextPeriodId(), 4);

        vm.stopPrank();
    }

    function testLabelStorage() public {
        vm.startPrank(allocationSetter);

        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});

        string
            memory longLabel = "This is a very long label that contains many characters to test string storage in the contract and ensure it handles long labels correctly without issues";

        incentive.setAllocations(1, longLabel, allocations, block.timestamp + 1, block.timestamp + 30 days);

        assertEq(incentive.periodLabels(1), longLabel);

        vm.stopPrank();
    }

    function testMixedAllocationSizes() public {
        vm.prank(allocationSetter);

        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](4);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1}); // 1 wei
        allocations[1] = IZoraIncentiveClaim.Allocation({user: user2, amount: 1000}); // 1000 wei
        allocations[2] = IZoraIncentiveClaim.Allocation({user: user3, amount: 1 ether}); // 1 ether
        allocations[3] = IZoraIncentiveClaim.Allocation({user: makeAddr("user4"), amount: 1000000 ether}); // 1M ether

        incentive.setAllocations(1, "Mixed Sizes", allocations, block.timestamp + 1, block.timestamp + 30 days);

        assertEq(incentive.periodAllocations(1, user1), 1);
        assertEq(incentive.periodAllocations(1, user2), 1000);
        assertEq(incentive.periodAllocations(1, user3), 1 ether);
        assertEq(incentive.periodAllocations(1, makeAddr("user4")), 1000000 ether);
    }

    function testEmptyStringLabel() public {
        vm.prank(allocationSetter);

        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});

        incentive.setAllocations(1, "", allocations, block.timestamp + 1, block.timestamp + 30 days);

        assertEq(incentive.periodLabels(1), "");
        assertEq(incentive.periodAllocations(1, user1), 1000 ether);
    }

    function testZeroAddressAllocationReverts() public {
        vm.prank(allocationSetter);

        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: address(0), amount: 1000 ether}); // Zero address

        vm.expectRevert(ZoraIncentiveClaim.ZeroAddress.selector);
        incentive.setAllocations(1, "Invalid Allocation", allocations, block.timestamp + 1, block.timestamp + 30 days);
    }

    function testInvalidTimeRangeReverts() public {
        vm.prank(allocationSetter);

        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});

        // Set start time AFTER end time to trigger InvalidTimeRange
        uint256 startTime = block.timestamp + 30 days;
        uint256 endTime = block.timestamp + 15 days; // Earlier than start

        vm.expectRevert(ZoraIncentiveClaim.InvalidTimeRange.selector);
        incentive.setAllocations(1, "Invalid Time Range", allocations, startTime, endTime);
    }

    function testUpdateAllocationsNonExistentPeriodReverts() public {
        vm.prank(allocationSetter);

        IZoraIncentiveClaim.Allocation[] memory allocations = new IZoraIncentiveClaim.Allocation[](1);
        allocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});

        // Try to update period that doesn't exist (periodId >= nextPeriodId)
        vm.expectRevert(abi.encodeWithSelector(ZoraIncentiveClaim.PeriodDoesNotExist.selector, 999));
        incentive.updateAllocations(999, allocations);
    }

    function testUpdateAllocationsZeroAddressReverts() public {
        // First create a period that starts in the future
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory setupAllocations = new IZoraIncentiveClaim.Allocation[](1);
        setupAllocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});
        incentive.setAllocations(1, "Test Period", setupAllocations, block.timestamp + 1 hours, block.timestamp + 30 days);

        // Try to update with zero address
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory updateAllocations = new IZoraIncentiveClaim.Allocation[](1);
        updateAllocations[0] = IZoraIncentiveClaim.Allocation({user: address(0), amount: 1000 ether});

        vm.expectRevert(ZoraIncentiveClaim.ZeroAddress.selector);
        incentive.updateAllocations(1, updateAllocations);
    }

    function testUpdateAllocationsZeroAmountAllowed() public {
        // First create a period that starts in the future
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory setupAllocations = new IZoraIncentiveClaim.Allocation[](1);
        setupAllocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});
        incentive.setAllocations(1, "Test Period", setupAllocations, block.timestamp + 1 hours, block.timestamp + 30 days);

        // Update with zero amount to remove user's allocation
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory updateAllocations = new IZoraIncentiveClaim.Allocation[](1);
        updateAllocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 0});

        incentive.updateAllocations(1, updateAllocations);

        // Verify user1's allocation was set to zero (removed)
        assertEq(incentive.periodAllocations(1, user1), 0);
    }

    function testUpdateAllocationsAfterPeriodStartsReverts() public {
        // Set a specific time to avoid underflow
        vm.warp(1000000); // Set to a large enough timestamp

        // Create a period that starts in the future and ends later
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory setupAllocations = new IZoraIncentiveClaim.Allocation[](1);
        setupAllocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});

        uint256 startTime = block.timestamp + 1; // Starts in the future (1000001)
        uint256 endTime = block.timestamp + 30 days;
        incentive.setAllocations(1, "Started Period", setupAllocations, startTime, endTime);

        // Move forward in time so period has definitely started
        vm.warp(startTime + 1);

        // Try to update allocations after period has started
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory updateAllocations = new IZoraIncentiveClaim.Allocation[](1);
        updateAllocations[0] = IZoraIncentiveClaim.Allocation({user: user2, amount: 2000 ether});

        // The error should contain the original startTime (1000001)
        vm.expectRevert(abi.encodeWithSelector(ZoraIncentiveClaim.PeriodAlreadyStarted.selector, 1, 1000001));
        incentive.updateAllocations(1, updateAllocations);
    }

    function testUpdateAllocationsBeforePeriodStartsSucceeds() public {
        // Create a period that starts in the future
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory setupAllocations = new IZoraIncentiveClaim.Allocation[](1);
        setupAllocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 1000 ether});

        uint256 startTime = block.timestamp + 1 hours; // Starts in 1 hour
        uint256 endTime = block.timestamp + 30 days;
        incentive.setAllocations(1, "Future Period", setupAllocations, startTime, endTime);

        // Should be able to update allocations before period starts
        vm.prank(allocationSetter);
        IZoraIncentiveClaim.Allocation[] memory updateAllocations = new IZoraIncentiveClaim.Allocation[](1);
        updateAllocations[0] = IZoraIncentiveClaim.Allocation({user: user1, amount: 2000 ether}); // Update user1's allocation

        incentive.updateAllocations(1, updateAllocations);

        // Verify the update worked - user1's allocation should be updated
        assertEq(incentive.periodAllocations(1, user1), 2000 ether); // Updated allocation
        assertEq(incentive.periodAllocations(1, user2), 0); // user2 has no allocation
    }
}
