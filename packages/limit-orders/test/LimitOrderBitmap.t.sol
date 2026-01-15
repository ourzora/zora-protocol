// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseTest} from "./utils/BaseTest.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LimitOrderBitmapTest is BaseTest {
    function test_bitmap_MultipleTicksInitialized() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create orders at 5 different ticks
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 5, 25e18);

        uint256 totalSize;
        for (uint256 i; i < orderSizes.length; ++i) {
            totalSize += orderSizes[i];
        }
        _fundAndApprove(users.seller, orderCoin, totalSize);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        bytes32 poolKeyHash = created[0].poolKeyHash;

        // Verify all ticks are initialized in bitmap
        for (uint256 i; i < orderTicks.length; ++i) {
            int24 fillableTick = _fillableTick(isCurrency0, orderTicks[i], key.tickSpacing);
            assertTrue(_isTickInitialized(poolKeyHash, orderCoin, fillableTick, key.tickSpacing), "tick should be initialized");
        }
    }

    function test_bitmap_ClearedWhenTickEmpty() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create single order
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 25e18);

        _fundAndApprove(users.seller, orderCoin, orderSizes[0]);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? orderSizes[0] : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        bytes32 poolKeyHash = created[0].poolKeyHash;

        // Verify tick is initialized
        int24 fillableTick = _fillableTick(isCurrency0, orderTicks[0], key.tickSpacing);
        assertTrue(_isTickInitialized(poolKeyHash, orderCoin, fillableTick, key.tickSpacing), "tick should be initialized after create");

        // Withdraw order
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = created[0].orderId;
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, users.seller);

        // Verify tick is cleared in bitmap
        assertFalse(_isTickInitialized(poolKeyHash, orderCoin, fillableTick, key.tickSpacing), "tick should be cleared after withdraw");
    }

    function test_bitmap_RemainsSetWithPartialOrders() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Create 2 orders at same tick
        int24 tick = _getValidTick(key, isCurrency0);
        uint256[] memory orderSizes = new uint256[](2);
        orderSizes[0] = 25e18;
        orderSizes[1] = 25e18;
        int24[] memory orderTicks = new int24[](2);
        orderTicks[0] = tick;
        orderTicks[1] = tick;

        uint256 totalSize = orderSizes[0] + orderSizes[1];
        _fundAndApprove(users.seller, orderCoin, totalSize);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, orderTicks, users.seller);

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        bytes32 poolKeyHash = created[0].poolKeyHash;

        // Withdraw first order only
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = created[0].orderId;
        vm.prank(users.seller);
        limitOrderBook.withdraw(orderIds, orderCoin, 0, users.seller);

        // Bitmap should still be set because second order remains
        int24 fillableTick = _fillableTick(isCurrency0, tick, key.tickSpacing);
        assertTrue(_isTickInitialized(poolKeyHash, orderCoin, fillableTick, key.tickSpacing), "tick should remain initialized with remaining order");
    }

    function test_bitmap_wordBoundaries() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);
        int24 spacing = key.tickSpacing;

        // Test ticks at word boundaries (words change every 256 ticks)
        // Word boundary occurs at tick = n * 256 * spacing
        int24[] memory boundaryTicks = new int24[](4);
        boundaryTicks[0] = 0; // word 0, bit 0
        boundaryTicks[1] = 255 * spacing; // word 0, bit 255 (last bit in word 0)
        boundaryTicks[2] = 256 * spacing; // word 1, bit 0 (first bit in word 1)
        boundaryTicks[3] = -256 * spacing; // word -1, bit 0

        uint256[] memory orderSizes = new uint256[](4);
        for (uint256 i = 0; i < 4; i++) {
            orderSizes[i] = 10e18;
        }

        uint256 totalSize = 40e18;
        _fundAndApprove(users.seller, orderCoin, totalSize);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, boundaryTicks, users.seller);

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        bytes32 poolKeyHash = created[0].poolKeyHash;

        // Verify all boundary ticks are initialized
        for (uint256 i = 0; i < boundaryTicks.length; i++) {
            int24 fillableTick = _fillableTick(isCurrency0, boundaryTicks[i], spacing);
            assertTrue(_isTickInitialized(poolKeyHash, orderCoin, fillableTick, spacing), "boundary tick should be initialized");
        }
    }

    function test_bitmap_extremeTicks() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);
        int24 spacing = key.tickSpacing;

        // Use ticks near the current tick but test extreme positions within range
        int24 currentTick = _currentTick(key);

        // Create ticks at far distances from current, but within reasonable range
        // For currency0 (sells), go far above current tick
        // For currency1 (sells), go far below current tick
        int24[] memory extremeTicks = new int24[](2);
        if (isCurrency0) {
            // Far above current tick
            extremeTicks[0] = _alignedTick(currentTick + (500 * spacing), spacing);
            extremeTicks[1] = _alignedTick(currentTick + (1000 * spacing), spacing);
        } else {
            // Far below current tick
            extremeTicks[0] = _alignedTick(currentTick - (500 * spacing), spacing);
            extremeTicks[1] = _alignedTick(currentTick - (1000 * spacing), spacing);
        }

        uint256[] memory orderSizes = new uint256[](2);
        orderSizes[0] = 10e18;
        orderSizes[1] = 10e18;

        uint256 totalSize = 20e18;
        _fundAndApprove(users.seller, orderCoin, totalSize);

        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, orderSizes, extremeTicks, users.seller);

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        bytes32 poolKeyHash = created[0].poolKeyHash;

        // Verify extreme ticks are initialized
        int24 fillableTick0 = _fillableTick(isCurrency0, extremeTicks[0], spacing);
        int24 fillableTick1 = _fillableTick(isCurrency0, extremeTicks[1], spacing);
        assertTrue(_isTickInitialized(poolKeyHash, orderCoin, fillableTick0, spacing), "far tick 1 should be initialized");
        assertTrue(_isTickInitialized(poolKeyHash, orderCoin, fillableTick1, spacing), "far tick 2 should be initialized");
    }

    function _fundAndApprove(address user, address token, uint256 amount) internal {
        if (token == address(0)) {
            vm.deal(user, amount);
        } else {
            deal(token, user, amount);
            vm.prank(user);
            IERC20(token).approve(address(limitOrderBook), amount);
        }
    }

    function _getValidTick(PoolKey memory key, bool isCurrency0) internal view returns (int24) {
        int24 currentTick = _currentTick(key);
        int24 offset = isCurrency0 ? key.tickSpacing * 2 : -key.tickSpacing * 2;
        int24 targetTick = currentTick + offset;
        return _alignedTick(targetTick, key.tickSpacing);
    }
}
