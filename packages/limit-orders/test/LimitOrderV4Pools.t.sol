// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseTest} from "./utils/BaseTest.sol";
import {LimitOrderCommon} from "../src/libs/LimitOrderCommon.sol";
import {CoinCommon} from "@zoralabs/coins/src/libs/CoinCommon.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LimitOrderV4PoolsTest is BaseTest {
    uint160 private constant INIT_SQRT_PRICE = 79228162514264337593543950336;

    function _buildPoolKey(address token0, address token1, IHooks hooks) internal pure returns (PoolKey memory) {
        bool isToken0Lower = token0 < token1;

        return
            PoolKey({
                currency0: Currency.wrap(isToken0Lower ? token0 : token1),
                currency1: Currency.wrap(isToken0Lower ? token1 : token0),
                fee: 10_000,
                tickSpacing: 200,
                hooks: hooks
            });
    }

    function test_existingPool_stillWorksAfterRemovingHookCheck() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = isCurrency0 ? address(creatorCoin) : Currency.unwrap(key.currency1);

        uint256[] memory orderSizes = new uint256[](1);
        orderSizes[0] = 50e18;

        int24 baseTick = _currentTick(key);
        baseTick = _alignedTick(baseTick, key.tickSpacing);

        int24[] memory orderTicks = new int24[](1);
        orderTicks[0] = _alignedTickForOrder(isCurrency0, baseTick, key.tickSpacing, 0);

        // Fund maker
        deal(orderCoin, users.seller, orderSizes[0]);
        vm.startPrank(users.seller);
        IERC20(orderCoin).approve(address(limitOrderBook), orderSizes[0]);
        vm.stopPrank();

        // Create order
        vm.prank(users.seller);
        bytes32[] memory orderIds = limitOrderBook.create(key, isCurrency0, orderSizes, orderTicks, users.seller);

        assertEq(orderIds.length, 1, "order not created");
    }

    function test_existingPool_fillWorksAfterPriceMovement() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(key, isCurrency0);

        // Build orders
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 2, 25e18);
        uint256 totalSize = orderSizes[0] + orderSizes[1];

        // Fund maker
        deal(orderCoin, users.seller, totalSize);
        vm.startPrank(users.seller);
        IERC20(orderCoin).approve(address(limitOrderBook), totalSize);
        vm.stopPrank();

        // Create orders
        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create(key, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());

        assertEq(created.length, 2, "expected 2 orders created");
        uint256 realizedSize = _sumOrderSizes(created);
        assertEq(_makerBalance(users.seller, orderCoin), realizedSize, "maker balance mismatch after create");

        uint256 previousMax = limitOrderBook.getMaxFillCount();
        limitOrderBook.setMaxFillCount(0); // Disable autofill

        address mover = makeAddr("price-mover");
        uint128 swapAmount = uint128(DEFAULT_LIMIT_ORDER_AMOUNT * 10);
        deal(address(zoraToken), mover, uint256(swapAmount));
        _swapSomeCurrencyForCoin(creatorCoin, address(zoraToken), swapAmount, mover);

        limitOrderBook.setMaxFillCount(previousMax); // Re-enable autofill

        // Get tick window for fills
        (int24 startTick, int24 endTick) = _tickWindow(created, key);
        bytes32 poolKeyHash = CoinCommon.hashPoolKey(key);
        uint256 epochBefore = _poolEpoch(poolKeyHash);

        // Fill orders
        vm.recordLogs();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, created.length, address(0));
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        // Verify fills
        assertEq(fills.length, created.length, "fill count mismatch");
        for (uint256 i; i < fills.length; ++i) {
            assertEq(fills[i].maker, users.seller, "maker mismatch");
            assertEq(fills[i].coinIn, orderCoin, "coin mismatch");
            assertEq(fills[i].fillReferral, address(0), "unexpected referral");
        }

        // Verify cleanup
        assertEq(_makerBalance(users.seller, orderCoin), 0, "maker balance should be zero after fill");
        assertGt(_poolEpoch(poolKeyHash), epochBefore, "pool epoch should increment");
    }

    function test_arbitraryPool_fillWithReferral() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = LimitOrderCommon.getOrderCoin(key, isCurrency0);

        // Build single order
        (uint256[] memory orderSizes, int24[] memory orderTicks) = _buildDeterministicOrders(key, isCurrency0, 1, 30e18);

        // Fund maker
        deal(orderCoin, users.seller, orderSizes[0]);
        vm.startPrank(users.seller);
        IERC20(orderCoin).approve(address(limitOrderBook), orderSizes[0]);
        vm.stopPrank();

        // Create order
        vm.recordLogs();
        vm.prank(users.seller);
        limitOrderBook.create(key, isCurrency0, orderSizes, orderTicks, users.seller);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());

        // Move price using disable/enable pattern
        uint256 previousMax = limitOrderBook.getMaxFillCount();
        limitOrderBook.setMaxFillCount(0);

        address mover = makeAddr("price-mover");
        uint128 swapAmount = uint128(DEFAULT_LIMIT_ORDER_AMOUNT * 10);
        deal(address(zoraToken), mover, uint256(swapAmount));
        _swapSomeCurrencyForCoin(creatorCoin, address(zoraToken), swapAmount, mover);

        limitOrderBook.setMaxFillCount(previousMax);

        // Fill with referral
        address referral = makeAddr("fillReferral");
        (int24 startTick, int24 endTick) = _tickWindow(created, key);

        vm.recordLogs();
        limitOrderBook.fill(key, isCurrency0, startTick, endTick, created.length, referral);
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        // Verify referral received fees
        assertEq(fills.length, 1, "expected 1 fill");
        assertEq(fills[0].fillReferral, referral, "referral address mismatch");
        assertGt(fills[0].fillReferralAmount, 0, "referral should receive fees");
    }
}
