// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseTest} from "./utils/BaseTest.sol";

import {IZoraLimitOrderBook} from "../src/IZoraLimitOrderBook.sol";
import {CoinCommon} from "@zoralabs/coins/src/libs/CoinCommon.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";

contract LimitOrderCreateTest is BaseTest {
    function test_create_prefundedViaAutosellCreatesOrders() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.buyer, key, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());

        assertGt(created.length, 0, "expected limit orders orders");
        for (uint256 i; i < created.length; ++i) {
            assertEq(created[i].maker, users.buyer, "maker mismatch");
            assertEq(created[i].coin, orderCoin, "coin mismatch");
        }

        uint256 realized = _sumOrderSizes(created);
        assertEq(_makerBalance(users.buyer, orderCoin), realized, "maker balance mismatch");
        _assertOpenOrderState(users.buyer, orderCoin, created[0].poolKeyHash, created, key.tickSpacing);
    }

    function test_create_pullsErc20FundsForExternalMaker() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        uint256[] memory orderSizes = new uint256[](2);
        orderSizes[0] = 40e18;
        orderSizes[1] = 25e18;
        uint256 totalSize = orderSizes[0] + orderSizes[1];

        int24 baseTick = _alignedTick(_currentTick(key), key.tickSpacing);
        int24[] memory orderTicks = new int24[](2);
        orderTicks[0] = isCurrency0 ? baseTick + key.tickSpacing : baseTick - key.tickSpacing;
        orderTicks[1] = isCurrency0 ? orderTicks[0] + key.tickSpacing : orderTicks[0] - key.tickSpacing;

        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.startPrank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
            vm.stopPrank();
        }

        vm.recordLogs();
        vm.prank(users.seller);
        bytes32[] memory orderIds = limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(
            key,
            isCurrency0,
            orderSizes,
            orderTicks,
            users.seller
        );

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertEq(created.length, orderIds.length, "mismatch between emitted and returned orders");

        uint256 realized = _sumOrderSizes(created);
        assertApproxEqAbs(realized, totalSize, 1, "realized size drift");
        assertEq(_makerBalance(users.seller, orderCoin), realized, "maker balance mismatch");
        _assertOpenOrderState(users.seller, orderCoin, CoinCommon.hashPoolKey(key), created, key.tickSpacing);
    }

    function test_create_refundsResidualAndIncrementsNonce() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        uint256[] memory orderSizes = new uint256[](3);
        orderSizes[0] = 123456789123456789;
        orderSizes[1] = 987654321987654321;
        orderSizes[2] = 222222222222222222;

        int24[] memory orderTicks = new int24[](3);
        int24 baseTick = _alignedTick(_currentTick(key), key.tickSpacing);
        for (uint256 i; i < orderTicks.length; ++i) {
            orderTicks[i] = _alignedTickForOrder(isCurrency0, baseTick, key.tickSpacing, i);
        }

        uint256 totalSize = orderSizes[0] + orderSizes[1] + orderSizes[2];
        deal(orderCoin, users.seller, totalSize);

        vm.startPrank(users.seller);
        IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        vm.stopPrank();

        uint256 nonceBefore = _makerNonce(users.seller);
        uint256 tokenBalanceBefore = IERC20(orderCoin).balanceOf(users.seller);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create(key, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertEq(created.length, orderSizes.length, "unexpected created order count");

        uint256 realized = _sumOrderSizes(created);
        uint256 residual = totalSize - realized;
        assertGt(residual, 0, "expected residual refund");

        assertEq(_makerBalance(users.seller, orderCoin), realized, "maker balance mismatch");
        assertEq(IERC20(orderCoin).balanceOf(users.seller), tokenBalanceBefore - totalSize + residual, "maker residual mismatch");
        assertEq(_makerNonce(users.seller), nonceBefore + orderSizes.length, "maker nonce mismatch");
    }

    function test_create_revertsWhenRealizedZero() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        uint256[] memory orderSizes = new uint256[](1);
        orderSizes[0] = 1;

        int24[] memory orderTicks = new int24[](1);
        orderTicks[0] = _alignedTick(_currentTick(key), key.tickSpacing);

        deal(orderCoin, users.seller, orderSizes[0]);
        vm.startPrank(users.seller);
        IERC20(orderCoin).approve(address(limitOrderBook), orderSizes[0]);
        vm.stopPrank();

        vm.expectRevert(IZoraLimitOrderBook.ZeroRealizedOrder.selector);
        vm.prank(users.seller);
        limitOrderBook.create(key, isCurrency0, orderSizes, orderTicks, users.seller);
    }

    function test_create_revertsOnZeroOrderSize() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);

        uint256[] memory orderSizes = new uint256[](1);
        orderSizes[0] = 0;

        int24[] memory orderTicks = new int24[](1);
        orderTicks[0] = _alignedTick(_currentTick(key), key.tickSpacing);

        vm.expectRevert(IZoraLimitOrderBook.ZeroOrderSize.selector);
        limitOrderBook.create(key, isCurrency0, orderSizes, orderTicks, users.seller);
    }

    function test_create_revertsOnArrayLengthMismatch() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);

        uint256[] memory orderSizes = new uint256[](2);
        orderSizes[0] = 1 ether;
        orderSizes[1] = 1 ether;

        int24[] memory orderTicks = new int24[](1);
        orderTicks[0] = _alignedTick(_currentTick(key), key.tickSpacing);

        vm.expectRevert(IZoraLimitOrderBook.ArrayLengthMismatch.selector);
        limitOrderBook.create(key, isCurrency0, orderSizes, orderTicks, users.seller);
    }

    function test_create_revertsOnZeroMaker() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);

        uint256[] memory orderSizes = new uint256[](1);
        orderSizes[0] = 1 ether;

        int24[] memory orderTicks = new int24[](1);
        orderTicks[0] = _alignedTick(_currentTick(key), key.tickSpacing);

        vm.expectRevert(IZoraLimitOrderBook.ZeroMaker.selector);
        limitOrderBook.create(key, isCurrency0, orderSizes, orderTicks, address(0));
    }

    function test_create_revertsOnZeroOrderSizeInBatch() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);

        uint256[] memory orderSizes = new uint256[](2);
        orderSizes[0] = 1 ether;
        orderSizes[1] = 0; // Zero size - invalid

        int24[] memory orderTicks = new int24[](2);
        orderTicks[0] = _alignedTick(_currentTick(key), key.tickSpacing);
        orderTicks[1] = orderTicks[0] + key.tickSpacing;

        vm.expectRevert(IZoraLimitOrderBook.ZeroOrderSize.selector);
        limitOrderBook.create(key, isCurrency0, orderSizes, orderTicks, users.seller);
    }

    function test_create_revertsOnExcessNativeValue() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Only test if order coin is native currency
        if (orderCoin != address(0)) {
            return; // Skip if not native
        }

        uint256[] memory orderSizes = new uint256[](1);
        orderSizes[0] = 1 ether;

        int24[] memory orderTicks = new int24[](1);
        int24 baseTick = _alignedTick(_currentTick(key), key.tickSpacing);
        orderTicks[0] = isCurrency0 ? baseTick + key.tickSpacing : baseTick - key.tickSpacing;

        vm.deal(users.seller, 2 ether);

        vm.prank(users.seller);
        vm.expectRevert(IZoraLimitOrderBook.NativeValueMismatch.selector);
        limitOrderBook.create{value: 2 ether}(key, isCurrency0, orderSizes, orderTicks, users.seller); // Too much value
    }

    function test_create_revertsOnInsufficientNativeValue() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Only test if order coin is native currency
        if (orderCoin != address(0)) {
            return; // Skip if not native
        }

        uint256[] memory orderSizes = new uint256[](1);
        orderSizes[0] = 1 ether;

        int24[] memory orderTicks = new int24[](1);
        int24 baseTick = _alignedTick(_currentTick(key), key.tickSpacing);
        orderTicks[0] = isCurrency0 ? baseTick + key.tickSpacing : baseTick - key.tickSpacing;

        vm.deal(users.seller, 0.5 ether);

        vm.prank(users.seller);
        vm.expectRevert(IZoraLimitOrderBook.NativeValueMismatch.selector);
        limitOrderBook.create{value: 0.5 ether}(key, isCurrency0, orderSizes, orderTicks, users.seller); // Too little value
    }

    function test_create_revertsOnInsufficientERC20Approval() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Only test if order coin is ERC20
        if (orderCoin == address(0)) {
            return; // Skip if native
        }

        uint256[] memory orderSizes = new uint256[](1);
        orderSizes[0] = 1 ether;

        int24[] memory orderTicks = new int24[](1);
        int24 baseTick = _alignedTick(_currentTick(key), key.tickSpacing);
        orderTicks[0] = isCurrency0 ? baseTick + key.tickSpacing : baseTick - key.tickSpacing;

        deal(orderCoin, users.seller, 1 ether);
        // Don't approve - should fail with ERC20 error

        vm.prank(users.seller);
        vm.expectRevert(); // ERC20 will throw standard error
        limitOrderBook.create(key, isCurrency0, orderSizes, orderTicks, users.seller);
    }

    function test_create_revertsOnInsufficientERC20Balance() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Only test if order coin is ERC20
        if (orderCoin == address(0)) {
            return; // Skip if native
        }

        uint256[] memory orderSizes = new uint256[](1);
        orderSizes[0] = 1 ether;

        int24[] memory orderTicks = new int24[](1);
        int24 baseTick = _alignedTick(_currentTick(key), key.tickSpacing);
        orderTicks[0] = isCurrency0 ? baseTick + key.tickSpacing : baseTick - key.tickSpacing;

        // Give only half the needed balance
        deal(orderCoin, users.seller, 0.5 ether);
        vm.startPrank(users.seller);
        IERC20(orderCoin).approve(address(limitOrderBook), 1 ether);

        vm.expectRevert(); // ERC20 will throw standard error
        limitOrderBook.create(key, isCurrency0, orderSizes, orderTicks, users.seller);
        vm.stopPrank();
    }

    function test_makerBalanceUpdated_emittedOnCreate() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        uint256[] memory orderSizes = new uint256[](3);
        orderSizes[0] = 100 ether;
        orderSizes[1] = 200 ether;
        orderSizes[2] = 150 ether;
        (, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, orderSizes.length, 1);

        uint256 totalSize;
        for (uint256 i; i < orderSizes.length; ++i) {
            totalSize += orderSizes[i];
        }

        if (orderCoin == address(0)) {
            vm.deal(users.seller, totalSize);
        } else {
            deal(orderCoin, users.seller, totalSize);
            vm.prank(users.seller);
            IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        }

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Find MakerBalanceUpdated events
        uint256 eventCount;
        uint256 finalBalance;

        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == IZoraLimitOrderBook.MakerBalanceUpdated.selector) {
                address eventMaker = address(uint160(uint256(logs[i].topics[1])));
                address eventCoin = address(uint160(uint256(logs[i].topics[2])));
                if (eventMaker == users.seller && eventCoin == orderCoin) {
                    finalBalance = abi.decode(logs[i].data, (uint256));
                    ++eventCount;
                }
            }
        }

        // Should have 3 events (one per order created)
        assertEq(eventCount, 3, "should emit 3 MakerBalanceUpdated events");
        assertEq(finalBalance, _makerBalance(users.seller, orderCoin), "final balance from event should match actual");
        assertGt(finalBalance, 0, "final balance should be positive after creation");
    }
}
