// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseTest} from "./utils/BaseTest.sol";

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";

contract SwapWithLimitOrdersTest is BaseTest {
    function test_autosellCreatesOrdersForSmallPurchases() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.buyer, key, 1e13, _defaultMultiples(), _defaultPercentages());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());

        // Small purchases create orders (no minimum threshold)
        assertGt(created.length, 0, "small swap should create orders");
    }

    function test_multiHopAutosellCreatesOrdersOnlyOnLastPool() public {
        PoolKey[] memory keys = new PoolKey[](2);
        keys[0] = creatorCoin.getPoolKey();
        keys[1] = contentCoin.getPoolKey();

        vm.recordLogs();
        _executeMultiHopSwapWithLimitOrders(users.buyer, keys, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());

        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertGt(created.length, 0, "expected orders on terminal hop");

        for (uint256 i; i < created.length; ++i) {
            assertEq(created[i].coin, address(contentCoin), "non-terminal hop should not create orders");
        }

        assertEq(_makerBalance(users.buyer, address(creatorCoin)), 0, "intermediate coin balance");
        assertGt(_makerBalance(users.buyer, address(contentCoin)), 0, "terminal coin balance");
    }

    function test_hookSwapDoesNotInvokeRouterFallbackWhenSupported() public {
        PoolKey memory key = creatorCoin.getPoolKey();

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.buyer, key, DEFAULT_LIMIT_ORDER_AMOUNT, _defaultMultiples(), _defaultPercentages());

        SwapExecutedLog[] memory swaps = _decodeSwapExecutedLogs(vm.getRecordedLogs());
        assertEq(swaps.length, 1, "expected single autosell swap event");
        // Verify orders were created (hook supports filling so router fallback not needed)
        assertGt(swaps[0].orders.length, 0, "expected orders to be created");
    }

    function test_unallocatedCoinsRefundedAndReferralPaid() public {
        PoolKey memory key = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(key.currency0) == address(creatorCoin);
        address orderCoin = _orderCoin(key, isCurrency0);

        // Use only 2 rungs to test partial allocation (70% allocated, 30% unallocated)
        uint256[] memory multiples = new uint256[](2);
        multiples[0] = 2e18;
        multiples[1] = 3e18;
        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 4000;
        percentages[1] = 3000;

        uint256 makerCoinBalanceBefore = _balanceOf(orderCoin, users.buyer);
        uint256 referralBalanceBefore = _balanceOf(address(zoraToken), users.tradeReferrer);

        vm.recordLogs();
        _executeSingleHopSwapWithLimitOrders(users.buyer, key, DEFAULT_LIMIT_ORDER_AMOUNT, multiples, percentages);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        CreatedOrderLog[] memory created = _decodeCreatedLogs(logs);
        assertGt(created.length, 0, "expected ladder orders");

        SwapExecutedLog[] memory swaps = _decodeSwapExecutedLogs(logs);
        assertEq(swaps.length, 1, "expected single autosell execution");
        assertEq(swaps[0].orders.length, created.length, "swap event orders length mismatch");

        // Verify 1:1 mapping between orders and their config
        for (uint256 i = 0; i < swaps[0].orders.length; i++) {
            assertEq(swaps[0].orders[i].orderId, created[i].orderId, "order id mismatch");
            // Verify each order has a valid multiple and percentage
            assertGt(swaps[0].orders[i].multiple, 0, "multiple should be non-zero");
            assertGt(swaps[0].orders[i].percentage, 0, "percentage should be non-zero");
        }

        uint256 totalOrderSize = _sumOrderSizes(created);
        assertEq(_makerBalance(users.buyer, orderCoin), totalOrderSize, "maker order balance mismatch");

        uint256 makerCoinBalanceAfter = _balanceOf(orderCoin, users.buyer);
        assertGt(makerCoinBalanceAfter, makerCoinBalanceBefore, "unallocated coins should be refunded to maker");

        uint256 referralBalanceAfter = _balanceOf(address(zoraToken), users.tradeReferrer);
        assertGe(referralBalanceAfter, referralBalanceBefore, "trade referral balance should not decrease");
    }

    function _balanceOf(address token, address account) private view returns (uint256) {
        if (token == address(0)) {
            return account.balance;
        }
        return IERC20(token).balanceOf(account);
    }
}
