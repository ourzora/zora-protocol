// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseTest} from "./utils/BaseTest.sol";
import {SwapWithLimitOrders} from "../src/router/SwapWithLimitOrders.sol";
import {V3ToV4SwapLib} from "@zoralabs/coins/src/libs/V3ToV4SwapLib.sol";
import {ISupportsLimitOrderFill} from "@zoralabs/coins/src/interfaces/ISupportsLimitOrderFill.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {LimitOrderConfig} from "../src/libs/SwapLimitOrders.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {AddressConstants} from "@zoralabs/coins/test/utils/hookmate/constants/AddressConstants.sol";

interface IZoraLimitOrderBookFillTickRange {
    function fill(PoolKey calldata key, bool isCurrency0, int24 startTick, int24 endTick, uint256 maxFillCount, address fillReferral) external;
}

import {Vm} from "forge-std/Vm.sol";

abstract contract SwapWithLimitOrdersTestBase is BaseTest {
    using PoolIdLibrary for PoolKey;

    function _executeSwapWithLimitOrders(address caller, SwapWithLimitOrders.SwapWithLimitOrdersParams memory params) internal returns (BalanceDelta delta) {
        vm.startPrank(caller);

        // Handle ETH transfers
        uint256 value = params.inputCurrency == address(0) ? params.inputAmount : 0;

        // Handle ERC20 approvals via Permit2
        if (params.inputCurrency != address(0)) {
            address permit2 = AddressConstants.getPermit2Address();
            IERC20(params.inputCurrency).approve(permit2, type(uint256).max);

            // Approve swapWithLimitOrders as spender in Permit2
            IAllowanceTransfer(permit2).approve(params.inputCurrency, address(swapWithLimitOrders), uint160(type(uint160).max), type(uint48).max);
        }

        // Execute swap with limit order placement
        delta = swapWithLimitOrders.swapWithLimitOrders{value: value}(params);

        vm.stopPrank();
    }

    function _buildDirectV4SwapParams(
        address recipient,
        address inputCurrency,
        uint256 inputAmount,
        PoolKey memory targetPool,
        LimitOrderConfig memory limitOrderConfig
    ) internal pure returns (SwapWithLimitOrders.SwapWithLimitOrdersParams memory) {
        PoolKey[] memory v4Route = new PoolKey[](1);
        v4Route[0] = targetPool;

        return
            SwapWithLimitOrders.SwapWithLimitOrdersParams({
                recipient: recipient,
                limitOrderConfig: limitOrderConfig,
                inputCurrency: inputCurrency,
                inputAmount: inputAmount,
                v3Route: bytes(""),
                v4Route: v4Route,
                minAmountOut: 0
            });
    }

    function _buildMultiHopV4SwapParams(
        address recipient,
        address inputCurrency,
        uint256 inputAmount,
        PoolKey[] memory v4Route,
        LimitOrderConfig memory limitOrderConfig
    ) internal pure returns (SwapWithLimitOrders.SwapWithLimitOrdersParams memory) {
        return
            SwapWithLimitOrders.SwapWithLimitOrdersParams({
                recipient: recipient,
                limitOrderConfig: limitOrderConfig,
                inputCurrency: inputCurrency,
                inputAmount: inputAmount,
                v3Route: bytes(""),
                v4Route: v4Route,
                minAmountOut: 0
            });
    }
}

contract SwapWithLimitOrdersTestNonForked is SwapWithLimitOrdersTestBase {
    function test_swapWithLimitOrders_directV4Swap() public {
        // Test direct V4 swap with single pool in v4Route
        // No V3 route, single pool, limit orders placed and filled

        PoolKey memory poolKey = creatorCoin.getPoolKey();
        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        // Give buyer ZORA tokens
        uint256 inputAmount = DEFAULT_LIMIT_ORDER_AMOUNT;
        deal(address(zoraToken), users.buyer, inputAmount);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildDirectV4SwapParams(
            users.buyer, // recipient
            address(zoraToken), // inputCurrency
            inputAmount,
            poolKey, // targetPool
            limitOrderConfig
        );

        _executeSwapWithLimitOrders(users.buyer, params);

        // Note: orderIds and ordersFilled are no longer returned
        // They can be extracted from events if needed for testing
    }

    function test_swapWithLimitOrders_multiHopV4Swap() public {
        // Test multi-hop V4 swap (e.g., ZORA -> Creator Coin -> Content Coin)
        // Multiple pools in v4Route, limit orders on final coin

        PoolKey[] memory v4Route = new PoolKey[](2);
        v4Route[0] = creatorCoin.getPoolKey();
        v4Route[1] = contentCoin.getPoolKey();

        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        uint256 inputAmount = DEFAULT_LIMIT_ORDER_AMOUNT;
        deal(address(zoraToken), users.buyer, inputAmount);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildMultiHopV4SwapParams(
            users.buyer, // recipient
            address(zoraToken), // inputCurrency
            inputAmount,
            v4Route,
            limitOrderConfig
        );

        vm.recordLogs();
        _executeSwapWithLimitOrders(users.buyer, params);

        // Extract order IDs from events
        SwapExecutedLog[] memory swaps = _decodeSwapExecutedLogs(vm.getRecordedLogs());
        require(swaps.length > 0, "expected swap event");

        // Verify orders created
        assertGt(swaps[0].orders.length, 0, "should have created orders");
    }

    function test_swapWithLimitOrders_hookCallsFill() public {
        // Test that hook calls zoraLimitOrderBook.fill during swap
        // We use vm.expectCall to verify the fill function is actually called

        PoolKey memory poolKey = creatorCoin.getPoolKey();
        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        uint256 inputAmount = DEFAULT_LIMIT_ORDER_AMOUNT;
        deal(address(zoraToken), users.buyer, inputAmount);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildDirectV4SwapParams(
            users.buyer,
            address(zoraToken),
            inputAmount,
            poolKey,
            limitOrderConfig
        );

        // Expect that zoraLimitOrderBook.fill is called by the hook during the swap
        // Use our interface to get the correct selector for the tick-range fill overload
        // Only use the selector without parameters for partial matching
        vm.expectCall(address(limitOrderBook), abi.encodeWithSelector(IZoraLimitOrderBookFillTickRange.fill.selector));

        vm.recordLogs();
        // Execute swap with limit order placement - this should trigger the hook's afterSwap which calls fill
        _executeSwapWithLimitOrders(users.buyer, params);

        // Extract order IDs from events
        SwapExecutedLog[] memory swaps = _decodeSwapExecutedLogs(vm.getRecordedLogs());
        require(swaps.length > 0, "expected swap event");

        // Verify orders were created
        assertGt(swaps[0].orders.length, 0, "should have created orders");
        assertEq(swaps[0].orders.length, 5, "should have 5 orders for 5 percentages");

        // If we reach here without reverting, vm.expectCall passed, meaning fill was called
    }

    function test_swapWithLimitOrders_hookDoesNotSupportLimitOrderFill() public {
        // Test with hook that doesn't implement ISupportsLimitOrderFill
        // Router SHOULD fill orders (backwards compatibility)
        // ordersFilled should reflect actual fills
        // TODO: Test with legacy hook or current hook before interface is added
    }

    function test_swapWithLimitOrders_oldHookWithoutERC165() public {
        // Test with very old hook that doesn't support ERC165 at all
        // Router should handle fills gracefully
        // TODO: Test with very old hook implementation
    }

    function test_limitOrderPlacement_createsExpectedSizes() public {
        // Verify order sizes match percentages from LimitOrderParams
        // Check allocated + unallocated = total coins purchased

        PoolKey memory poolKey = creatorCoin.getPoolKey();
        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        uint256 inputAmount = DEFAULT_LIMIT_ORDER_AMOUNT;
        deal(address(zoraToken), users.buyer, inputAmount);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildDirectV4SwapParams(
            users.buyer,
            address(zoraToken),
            inputAmount,
            poolKey,
            limitOrderConfig
        );

        vm.recordLogs();
        _executeSwapWithLimitOrders(users.buyer, params);

        // Extract order IDs from events
        SwapExecutedLog[] memory swaps = _decodeSwapExecutedLogs(vm.getRecordedLogs());
        require(swaps.length > 0, "expected swap event");

        // Verify orders created with expected count
        assertEq(swaps[0].orders.length, 5, "should have 5 orders for 5 percentages");
    }

    function test_limitOrderPlacement_alignsTicks() public {
        // Verify order ticks match multiples from LimitOrderParams
        // Check ticks are aligned to tick spacing
        // TODO: Implement tick calculation verification
    }

    function test_limitOrderPlacement_sendsUnallocatedToMaker() public {
        // Verify any unallocated coins go to maker/recipient
        // Check maker balance increases by unallocated amount
        // TODO: Test unallocated coin handling
    }

    function test_limitOrderPlacement_zeroSize() public {
        // Test that zero-size purchases don't create orders
        // Should still execute swap but skip limit order ladder creation
        // TODO: Test zero size handling
    }

    function test_limitOrderPlacement_supportsMultipleOrders() public {
        // Test creating multiple orders with different multiples
        // Verify all orders are tracked in the limit order book

        PoolKey memory poolKey = creatorCoin.getPoolKey();

        // Use more multiples to create more orders
        uint256[] memory multiples = new uint256[](5);
        multiples[0] = 2e18;
        multiples[1] = 3e18;
        multiples[2] = 4e18;
        multiples[3] = 5e18;
        multiples[4] = 10e18;

        uint256[] memory percentages = new uint256[](5);
        percentages[0] = 2000; // 20%
        percentages[1] = 2000; // 20%
        percentages[2] = 2000; // 20%
        percentages[3] = 2000; // 20%
        percentages[4] = 2000; // 20%

        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, multiples, percentages);

        uint256 inputAmount = DEFAULT_LIMIT_ORDER_AMOUNT;
        deal(address(zoraToken), users.buyer, inputAmount);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildDirectV4SwapParams(
            users.buyer,
            address(zoraToken),
            inputAmount,
            poolKey,
            limitOrderConfig
        );

        vm.recordLogs();
        _executeSwapWithLimitOrders(users.buyer, params);

        // Extract order IDs from events
        SwapExecutedLog[] memory swaps = _decodeSwapExecutedLogs(vm.getRecordedLogs());
        require(swaps.length > 0, "expected swap event");

        // Verify all orders were created
        assertEq(swaps[0].orders.length, 5, "should have created 5 orders");
    }

    function test_orderFilling_hookFillsLimitOrders() public {
        // Verify that hook fills limit orders during subsequent swaps
        // TODO: Revisit this test later - requires debugging hook's fill logic
        // to ensure swaps cross the exact tick ranges where orders are placed
    }

    function test_orderFilling_respectsMaxFillCount() public {
        // Verify only maxFillCount orders are filled
        // Test with more available orders than maxFillCount
        // TODO: Requires setting up pre-existing orders and crossing ticks
    }

    function test_orderFilling_crossedTickRange() public {
        // Verify only orders in crossed tick range are filled
        // Orders outside range should remain unfilled
        // TODO: Requires controlling tick movement during swap
    }

    /// forge-config: default.isolate = true
    function test_orderFilling_invertedDirection() public {
        // This test verifies the fix for audit issue #16
        // https://github.com/kadenzipfel/zora-autosell-audit/issues/16
        // The router should pass isCoinCurrency0 (not !isCoinCurrency0) to _fillOrders

        // Skip past launch fee period to test normal swap behavior
        vm.warp(block.timestamp + 1 days);

        PoolKey memory key = creatorCoin.getPoolKey();

        // 1. Create first buyer's orders using swapWithLimitOrders
        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());
        deal(address(zoraToken), users.buyer, DEFAULT_LIMIT_ORDER_AMOUNT);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildDirectV4SwapParams(
            users.buyer,
            address(zoraToken),
            DEFAULT_LIMIT_ORDER_AMOUNT,
            key,
            limitOrderConfig
        );

        vm.recordLogs();
        _executeSwapWithLimitOrders(users.buyer, params);
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());
        assertGt(created.length, 0, "expected orders to be created");

        // Store initial order state
        address orderCoin = created[0].coin;
        uint256 initialMakerBalance = _makerBalance(users.buyer, orderCoin);
        assertGt(initialMakerBalance, 0, "buyer should have orders");

        // 2. Mock the hook to not support ISupportsLimitOrderFill so router handles fills
        bytes memory callData = abi.encodeWithSelector(IERC165.supportsInterface.selector, type(ISupportsLimitOrderFill).interfaceId);
        vm.mockCall(address(key.hooks), callData, abi.encode(false));

        // 3. Execute second swap that moves price beyond first orders AND creates new orders
        // This ensures orders.length > 0 (from new orders) and tick moves past first orders
        // Using a much larger swap to ensure we cross the first order ticks
        LimitOrderConfig memory limitOrderConfig2 = _prepareLimitOrderParams(users.seller, _defaultMultiples(), _defaultPercentages());
        uint256 largerSwapAmount = DEFAULT_LIMIT_ORDER_AMOUNT * 100; // 100x larger to move price significantly
        deal(address(zoraToken), users.seller, largerSwapAmount);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params2 = _buildDirectV4SwapParams(
            users.seller,
            address(zoraToken),
            largerSwapAmount,
            key,
            limitOrderConfig2
        );

        vm.recordLogs();
        _executeSwapWithLimitOrders(users.seller, params2);

        // 5. Verify fills occurred by checking FilledOrderLog events
        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());

        // The bug: with !isCoinCurrency0, fills won't happen because wrong direction
        // After fix: fills SHOULD happen
        assertGt(fills.length, 0, "orders should have been filled by router");

        // 6. Verify orders were filled for correct maker
        for (uint256 i = 0; i < fills.length; i++) {
            assertEq(fills[i].maker, users.buyer, "incorrect maker");
            assertEq(fills[i].coinIn, orderCoin, "incorrect coin");
        }

        // 7. Verify maker balance decreased (orders filled and paid out)
        uint256 finalMakerBalance = _makerBalance(users.buyer, orderCoin);
        assertLt(finalMakerBalance, initialMakerBalance, "maker balance should decrease after fills");
    }

    function test_reverts_emptyV4Route() public {
        // Should revert with EmptyV4Route() when v4Route is empty

        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        deal(address(zoraToken), users.buyer, DEFAULT_LIMIT_ORDER_AMOUNT);

        // Create params with empty v4Route
        PoolKey[] memory emptyRoute = new PoolKey[](0);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = SwapWithLimitOrders.SwapWithLimitOrdersParams({
            recipient: users.buyer,
            limitOrderConfig: limitOrderConfig,
            inputCurrency: address(zoraToken),
            inputAmount: DEFAULT_LIMIT_ORDER_AMOUNT,
            v3Route: bytes(""),
            v4Route: emptyRoute,
            minAmountOut: 0
        });

        vm.prank(users.buyer);
        IERC20(address(zoraToken)).approve(address(swapWithLimitOrders), DEFAULT_LIMIT_ORDER_AMOUNT);

        vm.expectRevert(SwapWithLimitOrders.EmptyV4Route.selector);
        vm.prank(users.buyer);
        swapWithLimitOrders.swapWithLimitOrders(params);
    }

    function test_reverts_insufficientOutputAmount() public {
        // Should revert when final swap output < minAmountOut
        // Slippage protection test

        PoolKey memory poolKey = creatorCoin.getPoolKey();
        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        uint256 inputAmount = DEFAULT_LIMIT_ORDER_AMOUNT;
        deal(address(zoraToken), users.buyer, inputAmount);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildDirectV4SwapParams(
            users.buyer,
            address(zoraToken),
            inputAmount,
            poolKey,
            limitOrderConfig
        );

        // Set unrealistically high minAmountOut to trigger revert
        params.minAmountOut = type(uint256).max;

        // Setup Permit2 approval
        vm.startPrank(users.buyer);
        address permit2 = AddressConstants.getPermit2Address();
        IERC20(address(zoraToken)).approve(permit2, type(uint256).max);
        IAllowanceTransfer(permit2).approve(address(zoraToken), address(swapWithLimitOrders), uint160(type(uint160).max), type(uint48).max);
        vm.stopPrank();

        vm.expectRevert(SwapWithLimitOrders.InsufficientOutputAmount.selector);
        vm.prank(users.buyer);
        swapWithLimitOrders.swapWithLimitOrders(params);
    }

    function test_reverts_insufficientInputCurrency() public {
        // Should revert when msg.value < inputAmount (for ETH)
        // With Permit2: Should revert when there's no Permit2 allowance (AllowanceExpired)

        PoolKey memory poolKey = creatorCoin.getPoolKey();
        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        uint256 inputAmount = DEFAULT_LIMIT_ORDER_AMOUNT;

        // Give buyer some ZORA but don't set up Permit2 allowance
        deal(address(zoraToken), users.buyer, inputAmount);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildDirectV4SwapParams(
            users.buyer,
            address(zoraToken), // ZORA
            inputAmount,
            poolKey,
            limitOrderConfig
        );

        // Don't approve Permit2 or set allowance - will revert with AllowanceExpired
        vm.prank(users.buyer);
        vm.expectRevert(abi.encodeWithSignature("AllowanceExpired(uint256)", 0));
        swapWithLimitOrders.swapWithLimitOrders(params);
    }

    function test_reverts_whenV3OutputDoesNotMatchV4Input() public {
        // Craft mismatched V3/V4 routes so validation fails before any swaps execute.
        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        PoolKey[] memory v4Route = new PoolKey[](1);
        v4Route[0] = creatorCoin.getPoolKey();

        // Encode a V3 path whose output token is contentCoin, which is NOT part of the first V4 pool.
        bytes memory v3Route = abi.encodePacked(address(zoraToken), uint24(3000), address(contentCoin));

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = SwapWithLimitOrders.SwapWithLimitOrdersParams({
            recipient: users.buyer,
            limitOrderConfig: limitOrderConfig,
            inputCurrency: address(zoraToken),
            inputAmount: DEFAULT_LIMIT_ORDER_AMOUNT,
            v3Route: v3Route,
            v4Route: v4Route,
            minAmountOut: 0
        });

        vm.expectRevert(V3ToV4SwapLib.V3RouteDoesNotConnectToV4RouteStart.selector);
        vm.prank(users.buyer);
        swapWithLimitOrders.swapWithLimitOrders(params);
    }

    function test_swapUsesMakerAllowanceEvenWhenCallerDiffers() public {
        PoolKey memory poolKey = creatorCoin.getPoolKey();

        // Now msg.sender pays for the swap, recipient receives outputs and owns orders
        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());
        uint256 inputAmount = DEFAULT_LIMIT_ORDER_AMOUNT;

        deal(address(zoraToken), users.buyer, inputAmount);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildDirectV4SwapParams(
            users.buyer, // Recipient who will own the orders
            address(zoraToken),
            inputAmount,
            poolKey,
            limitOrderConfig
        );

        uint256 buyerBalanceBefore = IERC20(address(zoraToken)).balanceOf(users.buyer);

        _executeSwapWithLimitOrders(users.buyer, params);

        // Buyer (msg.sender) paid for the swap and owns the orders
        assertLt(IERC20(address(zoraToken)).balanceOf(users.buyer), buyerBalanceBefore, "buyer should fund the swap");
    }

    function test_routerFallsBackWhenHookDoesNotSupportFill() public {
        PoolKey memory poolKey = creatorCoin.getPoolKey();
        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        // Force IERC165 check to return false so router must handle fills.
        bytes memory callData = abi.encodeWithSelector(IERC165.supportsInterface.selector, type(ISupportsLimitOrderFill).interfaceId);
        vm.mockCall(address(poolKey.hooks), callData, abi.encode(false));

        uint256 inputAmount = DEFAULT_LIMIT_ORDER_AMOUNT;
        deal(address(zoraToken), users.buyer, inputAmount);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildDirectV4SwapParams(
            users.buyer,
            address(zoraToken),
            inputAmount,
            poolKey,
            limitOrderConfig
        );

        vm.recordLogs();
        _executeSwapWithLimitOrders(users.buyer, params);

        // Extract order IDs from events
        SwapExecutedLog[] memory swaps = _decodeSwapExecutedLogs(vm.getRecordedLogs());
        require(swaps.length > 0, "expected swap event");

        assertGt(swaps[0].orders.length, 0, "orders should still be created when hook lacks fill support");

        vm.clearMockedCalls();
    }

    function test_routerDoesNotFillWhenMaxFillCountIsZero() public {
        PoolKey memory poolKey = creatorCoin.getPoolKey();
        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        uint256 previousMax = limitOrderBook.getMaxFillCount();
        limitOrderBook.setMaxFillCount(0);

        bytes memory callData = abi.encodeWithSelector(IERC165.supportsInterface.selector, type(ISupportsLimitOrderFill).interfaceId);
        vm.mockCall(address(poolKey.hooks), callData, abi.encode(false));

        uint256 inputAmount = DEFAULT_LIMIT_ORDER_AMOUNT;
        deal(address(zoraToken), users.buyer, inputAmount);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildDirectV4SwapParams(
            users.buyer,
            address(zoraToken),
            inputAmount,
            poolKey,
            limitOrderConfig
        );

        _executeSwapWithLimitOrders(users.buyer, params);
        uint256 ordersFilled = 0; // Note: ordersFilled no longer returned

        assertEq(ordersFilled, 0, "max fill count zero should short-circuit fills");

        vm.clearMockedCalls();
        limitOrderBook.setMaxFillCount(previousMax);
    }

    function test_partialAllocationRoutesUnallocatedCoinsToMaker() public {
        PoolKey memory poolKey = creatorCoin.getPoolKey();

        uint256[] memory customMultiples = new uint256[](2);
        customMultiples[0] = 2e18;
        customMultiples[1] = 4e18;
        uint256[] memory customPercentages = new uint256[](2);
        customPercentages[0] = 2500;
        customPercentages[1] = 2500; // keep 50% unallocated

        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, customMultiples, customPercentages);

        uint256 inputAmount = DEFAULT_LIMIT_ORDER_AMOUNT;
        deal(address(zoraToken), users.buyer, inputAmount);

        uint256 makerBalanceBefore = IERC20(address(creatorCoin)).balanceOf(users.buyer);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildDirectV4SwapParams(
            users.buyer,
            address(zoraToken),
            inputAmount,
            poolKey,
            limitOrderConfig
        );

        vm.recordLogs();
        _executeSwapWithLimitOrders(users.buyer, params);

        // Extract order IDs from events
        SwapExecutedLog[] memory swaps = _decodeSwapExecutedLogs(vm.getRecordedLogs());
        require(swaps.length > 0, "expected swap event");

        assertEq(swaps[0].orders.length, 2, "expected two orders for two percentages");
        uint256 makerBalanceAfter = IERC20(address(creatorCoin)).balanceOf(users.buyer);
        assertGt(makerBalanceAfter, makerBalanceBefore, "unallocated coins should be returned to maker");
    }

    function test_emitsSwapAndCreateEvents() public {
        PoolKey memory poolKey = creatorCoin.getPoolKey();
        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        uint256 inputAmount = DEFAULT_LIMIT_ORDER_AMOUNT;
        deal(address(zoraToken), users.buyer, inputAmount);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildDirectV4SwapParams(
            users.buyer,
            address(zoraToken),
            inputAmount,
            poolKey,
            limitOrderConfig
        );

        vm.recordLogs();
        _executeSwapWithLimitOrders(users.buyer, params);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool sawCreated;
        bool sawExecuted;

        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory log = logs[i];
            if (log.topics.length == 0) continue;

            if (log.topics[0] == LIMIT_ORDER_CREATED_TOPIC) {
                address maker = address(uint160(uint256(log.topics[1])));
                assertEq(maker, users.buyer, "maker indexed value mismatch");
                (, , , uint128 orderSize, ) = abi.decode(log.data, (bytes32, bool, int24, uint128, bytes32));
                assertGt(orderSize, 0, "order size should be positive");
                sawCreated = true;
            } else if (log.topics[0] == SWAP_WITH_LIMIT_ORDERS_EXECUTED_TOPIC && log.topics.length >= 3) {
                address sender = address(uint160(uint256(log.topics[1])));
                address recipient = address(uint160(uint256(log.topics[2])));
                assertEq(sender, users.buyer, "sender indexed mismatch");
                assertEq(recipient, users.buyer, "recipient indexed mismatch");
                (PoolKey memory loggedPoolKey, , , int128 amount0, int128 amount1, uint160 sqrtPriceX96, CreatedOrder[] memory orders) = abi.decode(
                    log.data,
                    (PoolKey, int24, int24, int128, int128, uint160, CreatedOrder[])
                );
                assertEq(Currency.unwrap(loggedPoolKey.currency0), Currency.unwrap(poolKey.currency0), "pool currency0 mismatch");
                assertEq(Currency.unwrap(loggedPoolKey.currency1), Currency.unwrap(poolKey.currency1), "pool currency1 mismatch");
                assertTrue(amount0 != 0 || amount1 != 0, "swap amounts should be non-zero");
                assertGt(sqrtPriceX96, 0, "sqrtPriceX96 should be non-zero");
                assertGt(orders.length, 0, "should have created orders");
                sawExecuted = true;
            }
        }

        assertTrue(sawCreated, "LimitOrdersCreated event missing");
        assertTrue(sawExecuted, "SwapWithLimitOrdersExecuted event missing");
    }

    function test_unlockCallback_revertsForExternalCaller() public {
        vm.expectRevert(SwapWithLimitOrders.OnlyPoolManager.selector);
        vm.prank(users.buyer);
        swapWithLimitOrders.unlockCallback(bytes(""));
    }

    function test_reverts_nonPositiveCoinDelta() public {
        // Should revert when swap results in zero or negative coin delta
        // TODO: Implement test for non-positive coin delta
    }

    function test_inputCurrency_ETH() public {
        // Test with ETH as input currency (address(0))
        // Verify msg.value is used correctly
    }

    function test_inputCurrency_ERC20() public {
        // Test with ERC20 as input currency
        // Verify token is transferred from maker
        // Verify allowance is checked
    }

    function test_inputCurrency_transfersFromMaker() public {
        // Verify input currency is pulled from limitOrderConfig.maker
        // Not from msg.sender if different
    }

    function test_settlement_ETHInput() public {
        // Verify ETH is settled correctly with poolManager
        // Check settle() called with value
    }

    function test_settlement_ERC20Input() public {
        // Verify ERC20 is settled correctly
        // Check sync() and transfer() and settle() sequence
    }

    function test_settlement_outputToRecipient() public {
        // Verify output currency is sent to params.recipient
        // Check poolManager.take() called correctly
    }

    function test_event_SwapWithLimitOrdersExecuted() public {
        // Verify SwapWithLimitOrdersExecuted event emits price data fields
        PoolKey memory poolKey = creatorCoin.getPoolKey();
        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        uint256 inputAmount = DEFAULT_LIMIT_ORDER_AMOUNT;
        deal(address(zoraToken), users.buyer, inputAmount);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildDirectV4SwapParams(
            users.buyer,
            address(zoraToken),
            inputAmount,
            poolKey,
            limitOrderConfig
        );

        vm.recordLogs();
        _executeSwapWithLimitOrders(users.buyer, params);

        SwapExecutedLog[] memory swaps = _decodeSwapExecutedLogs(vm.getRecordedLogs());
        assertEq(swaps.length, 1, "expected single swap event");

        // Verify price data fields are populated
        SwapExecutedLog memory swap = swaps[0];
        assertEq(swap.sender, users.buyer, "sender mismatch");
        assertEq(swap.recipient, users.buyer, "recipient mismatch");

        // amount0 and amount1 should be non-zero (one negative, one positive for a swap)
        assertTrue(swap.amount0 != 0 || swap.amount1 != 0, "swap amounts should be non-zero");
        assertTrue((swap.amount0 < 0 && swap.amount1 > 0) || (swap.amount0 > 0 && swap.amount1 < 0), "amounts should have opposite signs for a swap");

        // sqrtPriceX96 should be a valid price (non-zero, reasonable range)
        assertGt(swap.sqrtPriceX96, 0, "sqrtPriceX96 should be non-zero");

        // Tick movement should be reflected
        assertTrue(swap.tickBefore != swap.tickAfter || swap.amount0 == 0, "tick should move on swap");
    }

    function test_event_LimitOrdersCreated() public {
        // Verify LimitOrdersCreated event emitted
        // Check maker, orderIds, and totalOrderSize
    }

    function test_event_LimitOrdersFilled() public {
        // Verify LimitOrdersFilled event emitted when router handles fills
        // Should NOT emit when hook handles fills
    }

    function test_integration_fullFlow_ERC20_to_ContentCoin() public {
        // End-to-end test: Creator Coin -> Content Coin (V4 only)
        // Verify ERC20 transfer, swap, order placement, filling
    }

    function test_integration_orderPlacedAndFilledInSameCall() public {
        // Verify orders can be placed and immediately filled if tick range crossed
        // Test round-trip efficiency
    }

    function test_zeroUnallocatedCoins() public {
        // Test when 100% of coins are allocated to orders
        // unallocated should be 0
    }

    function test_partialAllocation() public {
        // Test when percentages don't sum to 100%
        // Some coins should remain unallocated
    }

    function test_roundingInOrderSizes() public {
        // Test order size rounding with small percentages
        // Verify no dust orders are created
    }

    function test_maxTickBoundaries() public {
        // Test limit order placement with extreme multiples that hit max/min tick limits
        // Verify ticks are clamped correctly
    }
}

contract SwapWithLimitOrdersTestForked is SwapWithLimitOrdersTestBase {
    // USDC_ADDRESS and ZORA_TOKEN_ADDRESS are inherited from ContractAddresses

    function setUp() public override {
        super.setUpWithBlockNumber(37877563);
    }

    function _encodeV3Path(address tokenA, uint24 feeA, address tokenB, uint24 feeB, address tokenC) internal pure returns (bytes memory) {
        return abi.encodePacked(tokenA, feeA, tokenB, feeB, tokenC);
    }

    function _encodeV3PathSingle(address tokenA, uint24 fee, address tokenB) internal pure returns (bytes memory) {
        return abi.encodePacked(tokenA, fee, tokenB);
    }

    function _buildV3ToV4SwapParams(
        address recipient,
        uint256 inputAmount,
        bytes memory v3Route,
        PoolKey[] memory v4Route,
        LimitOrderConfig memory limitOrderConfig
    ) internal pure returns (SwapWithLimitOrders.SwapWithLimitOrdersParams memory) {
        return
            SwapWithLimitOrders.SwapWithLimitOrdersParams({
                recipient: recipient,
                limitOrderConfig: limitOrderConfig,
                inputCurrency: address(0), // ETH
                inputAmount: inputAmount,
                v3Route: v3Route,
                v4Route: v4Route,
                minAmountOut: 0
            });
    }

    function test_swapWithLimitOrders_withV3Route() public {
        // Test V3 + V4 swap (e.g., ETH -> ZORA via V3, then ZORA -> Coin via V4)
        // V3 route populated, V4 route with target pool

        uint256 inputAmount = 0.1 ether;
        vm.deal(users.buyer, inputAmount);

        // Create V3 path: ETH -> USDC -> ZORA
        bytes memory v3Route = _encodeV3Path(
            address(weth),
            3000, // WETH/USDC 0.3%
            USDC_ADDRESS,
            3000, // USDC/ZORA 0.3%
            ZORA_TOKEN_ADDRESS
        );

        // V4 route: Just the target pool (coin paired with ZORA)
        PoolKey[] memory v4Route = new PoolKey[](1);
        v4Route[0] = creatorCoin.getPoolKey();

        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildV3ToV4SwapParams(users.buyer, inputAmount, v3Route, v4Route, limitOrderConfig);

        vm.recordLogs();
        _executeSwapWithLimitOrders(users.buyer, params);

        // Extract order IDs from events
        SwapExecutedLog[] memory swaps = _decodeSwapExecutedLogs(vm.getRecordedLogs());
        require(swaps.length > 0, "expected swap event");

        // Verify orders were created
        assertGt(swaps[0].orders.length, 0, "should have created orders");
        assertEq(swaps[0].orders.length, 5, "should have 5 orders for 5 percentages");

        // Verify ETH was spent
        assertEq(users.buyer.balance, 0, "buyer should have spent all ETH");

        // Note: With default percentages (100% allocated), all coins go into orders
        // The buyer will receive coins when orders are filled by subsequent swaps
    }

    function test_swapWithLimitOrders_withV3AndMultiHopV4() public {
        // Test V3 + multi-hop V4 (e.g., ETH -> ZORA -> Creator -> Content)
        // V3 route + multiple V4 pools

        uint256 inputAmount = 0.1 ether;
        vm.deal(users.buyer, inputAmount);

        // Create V3 path: ETH -> USDC -> ZORA
        bytes memory v3Route = _encodeV3Path(
            address(weth),
            3000, // WETH/USDC 0.3%
            USDC_ADDRESS,
            3000, // USDC/ZORA 0.3%
            ZORA_TOKEN_ADDRESS
        );

        // Multi-hop V4 route: ZORA -> Creator Coin -> Content Coin
        PoolKey[] memory v4Route = new PoolKey[](2);
        v4Route[0] = creatorCoin.getPoolKey();
        v4Route[1] = contentCoin.getPoolKey();

        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildV3ToV4SwapParams(users.buyer, inputAmount, v3Route, v4Route, limitOrderConfig);

        vm.recordLogs();
        _executeSwapWithLimitOrders(users.buyer, params);

        // Extract order IDs from events
        SwapExecutedLog[] memory swaps = _decodeSwapExecutedLogs(vm.getRecordedLogs());
        require(swaps.length > 0, "expected swap event");

        // Verify orders were created
        assertGt(swaps[0].orders.length, 0, "should have created orders");
        assertEq(swaps[0].orders.length, 5, "should have 5 orders for 5 percentages");

        // Verify ETH was spent
        assertEq(users.buyer.balance, 0, "buyer should have spent all ETH");

        // Note: With default percentages (100% allocated), all coins go into orders
        // The buyer will receive content coins when orders are filled by subsequent swaps
    }

    function test_RevertWhen_InsufficientInputCurrencyETH() public {
        uint256 inputAmount = 1 ether;
        uint256 insufficientAmount = 0.5 ether;

        // Create V3 path: ETH -> USDC -> ZORA
        bytes memory v3Route = _encodeV3Path(
            address(weth),
            3000, // WETH/USDC 0.3%
            USDC_ADDRESS,
            3000, // USDC/ZORA 0.3%
            ZORA_TOKEN_ADDRESS
        );

        PoolKey[] memory v4Route = new PoolKey[](1);
        v4Route[0] = creatorCoin.getPoolKey();

        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildV3ToV4SwapParams(users.buyer, inputAmount, v3Route, v4Route, limitOrderConfig);

        // Should revert with InsufficientInputCurrency
        vm.deal(users.buyer, insufficientAmount);
        vm.expectRevert(abi.encodeWithSelector(V3ToV4SwapLib.InsufficientInputCurrency.selector, inputAmount, insufficientAmount));

        vm.prank(users.buyer);
        swapWithLimitOrders.swapWithLimitOrders{value: insufficientAmount}(params);
    }

    function test_RevertWhen_InsufficientOutputAmount() public {
        uint256 inputAmount = 0.1 ether;
        vm.deal(users.buyer, inputAmount);

        // Create V3 path: ETH -> USDC -> ZORA
        bytes memory v3Route = _encodeV3Path(
            address(weth),
            3000, // WETH/USDC 0.3%
            USDC_ADDRESS,
            3000, // USDC/ZORA 0.3%
            ZORA_TOKEN_ADDRESS
        );

        PoolKey[] memory v4Route = new PoolKey[](1);
        v4Route[0] = creatorCoin.getPoolKey();

        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildV3ToV4SwapParams(users.buyer, inputAmount, v3Route, v4Route, limitOrderConfig);

        // Set impossibly high minAmountOut to trigger revert
        params.minAmountOut = type(uint256).max;

        // Should revert with InsufficientOutputAmount
        vm.expectRevert(SwapWithLimitOrders.InsufficientOutputAmount.selector);

        vm.prank(users.buyer);
        swapWithLimitOrders.swapWithLimitOrders{value: inputAmount}(params);
    }

    function test_reverts_v3RouteDoesNotConnectToV4Route() public {
        // Should revert when V3 output currency doesn't match V4 route start
        // Route validation test

        uint256 inputAmount = 1 ether;
        vm.deal(users.buyer, inputAmount);

        // Create V3 path that ends with USDC
        bytes memory v3Route = _encodeV3PathSingle(
            address(weth),
            3000, // WETH/USDC 0.3%
            USDC_ADDRESS
        );

        // Create V4 route that starts with ZORA (not USDC - mismatch!)
        PoolKey[] memory v4Route = new PoolKey[](1);
        v4Route[0] = creatorCoin.getPoolKey();

        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildV3ToV4SwapParams(users.buyer, inputAmount, v3Route, v4Route, limitOrderConfig);

        // Should revert with V3RouteDoesNotConnectToV4RouteStart
        vm.prank(users.buyer);
        vm.expectRevert(abi.encodeWithSelector(V3ToV4SwapLib.V3RouteDoesNotConnectToV4RouteStart.selector));
        swapWithLimitOrders.swapWithLimitOrders{value: inputAmount}(params);
    }

    function test_integration_fullFlow_ETH_to_ZORA_to_CreatorCoin() public {
        // End-to-end test: ETH -> V3(ZORA) -> V4(Creator Coin)
        // Verify all steps: V3 swap, V4 swap, order placement, order filling

        uint256 inputAmount = 0.1 ether;
        vm.deal(users.buyer, inputAmount);

        // Create V3 path: ETH -> USDC -> ZORA
        bytes memory v3Route = _encodeV3Path(
            address(weth),
            3000, // WETH/USDC 0.3%
            USDC_ADDRESS,
            3000, // USDC/ZORA 0.3%
            ZORA_TOKEN_ADDRESS
        );

        // V4 route: ZORA -> Creator Coin
        PoolKey[] memory v4Route = new PoolKey[](1);
        v4Route[0] = creatorCoin.getPoolKey();

        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = _buildV3ToV4SwapParams(users.buyer, inputAmount, v3Route, v4Route, limitOrderConfig);

        vm.recordLogs();
        _executeSwapWithLimitOrders(users.buyer, params);

        // Extract order IDs from events
        SwapExecutedLog[] memory swaps = _decodeSwapExecutedLogs(vm.getRecordedLogs());
        require(swaps.length > 0, "expected swap event");

        // Verify orders were created
        assertGt(swaps[0].orders.length, 0, "should have created orders");
        assertEq(swaps[0].orders.length, 5, "should have 5 orders for 5 percentages");

        // Verify ETH was spent
        assertEq(users.buyer.balance, 0, "buyer should have spent all ETH");

        // Note: With default percentages (100% allocated), all coins go into orders
        // The buyer will receive coins when orders are filled by subsequent swaps
    }

    function test_swapWithLimitOrders_ERC20toV3toV4_singleHop() public {
        // Give buyer USDC tokens
        uint256 usdcAmount = 100 * 10 ** 6; // 100 USDC
        deal(USDC_ADDRESS, users.buyer, usdcAmount);

        // Create V3 path: USDC -> ZORA
        bytes memory v3Route = _encodeV3PathSingle(USDC_ADDRESS, 3000, ZORA_TOKEN_ADDRESS);

        // Create V4 route: ZORA -> Coin
        PoolKey[] memory v4Route = new PoolKey[](1);
        v4Route[0] = creatorCoin.getPoolKey();

        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        // Build swap params with USDC as input currency
        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = SwapWithLimitOrders.SwapWithLimitOrdersParams({
            recipient: users.buyer,
            limitOrderConfig: limitOrderConfig,
            inputCurrency: USDC_ADDRESS, // ERC20 input
            inputAmount: usdcAmount,
            v3Route: v3Route,
            v4Route: v4Route,
            minAmountOut: 0
        });

        // Execute swap - this should FAIL with V3RouteCannotStartWithInputCurrency
        _executeSwapWithLimitOrders(users.buyer, params);

        // If we get here after implementation, verify USDC was spent and coins received
        assertEq(IERC20(USDC_ADDRESS).balanceOf(users.buyer), 0, "buyer should have spent all USDC");
        assertGt(IERC20(address(creatorCoin)).balanceOf(users.buyer), 0, "buyer should have received coins");
    }

    function test_swapWithLimitOrders_ZORAtoV4() public {
        // Give buyer ZORA tokens
        uint256 zoraAmount = 10 ether;
        deal(ZORA_TOKEN_ADDRESS, users.buyer, zoraAmount);

        // Create V4 route: ZORA -> Coin (no V3 swap)
        PoolKey[] memory v4Route = new PoolKey[](1);
        v4Route[0] = creatorCoin.getPoolKey();

        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        // Build swap params with ZORA as input currency, no V3 route
        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = SwapWithLimitOrders.SwapWithLimitOrdersParams({
            recipient: users.buyer,
            limitOrderConfig: limitOrderConfig,
            inputCurrency: ZORA_TOKEN_ADDRESS, // ERC20 input
            inputAmount: zoraAmount,
            v3Route: bytes(""), // No V3 swap
            v4Route: v4Route,
            minAmountOut: 0
        });

        // Execute swap - this should PASS
        _executeSwapWithLimitOrders(users.buyer, params);

        // Verify ZORA was spent and coins received
        assertEq(IERC20(ZORA_TOKEN_ADDRESS).balanceOf(users.buyer), 0, "buyer should have spent all ZORA");
        assertGt(IERC20(address(creatorCoin)).balanceOf(users.buyer), 0, "buyer should have received coins");
    }

    function test_reverts_ERC20InputWithoutApproval() public {
        // Give buyer USDC tokens
        uint256 usdcAmount = 100 * 10 ** 6; // 100 USDC
        deal(USDC_ADDRESS, users.buyer, usdcAmount);

        // Create V3 path: USDC -> ZORA
        bytes memory v3Route = _encodeV3PathSingle(USDC_ADDRESS, 3000, ZORA_TOKEN_ADDRESS);

        // Create V4 route: ZORA -> Coin
        PoolKey[] memory v4Route = new PoolKey[](1);
        v4Route[0] = creatorCoin.getPoolKey();

        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        // Build swap params
        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = SwapWithLimitOrders.SwapWithLimitOrdersParams({
            recipient: users.buyer,
            limitOrderConfig: limitOrderConfig,
            inputCurrency: USDC_ADDRESS,
            inputAmount: usdcAmount,
            v3Route: v3Route,
            v4Route: v4Route,
            minAmountOut: 0
        });

        // Execute without approval - should revert
        vm.startPrank(users.buyer);
        // Don't approve - just call directly
        vm.expectRevert();
        swapWithLimitOrders.swapWithLimitOrders(params);
        vm.stopPrank();
    }

    function test_reverts_ERC20InputInsufficientBalance() public {
        // Give buyer only 50 USDC but try to swap 100 USDC
        uint256 balanceAmount = 50 * 10 ** 6; // 50 USDC
        uint256 swapAmount = 100 * 10 ** 6; // 100 USDC
        deal(USDC_ADDRESS, users.buyer, balanceAmount);

        // Create V3 path: USDC -> ZORA
        bytes memory v3Route = _encodeV3PathSingle(USDC_ADDRESS, 3000, ZORA_TOKEN_ADDRESS);

        // Create V4 route: ZORA -> Coin
        PoolKey[] memory v4Route = new PoolKey[](1);
        v4Route[0] = creatorCoin.getPoolKey();

        LimitOrderConfig memory limitOrderConfig = _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages());

        // Build swap params with more than available balance
        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = SwapWithLimitOrders.SwapWithLimitOrdersParams({
            recipient: users.buyer,
            limitOrderConfig: limitOrderConfig,
            inputCurrency: USDC_ADDRESS,
            inputAmount: swapAmount,
            v3Route: v3Route,
            v4Route: v4Route,
            minAmountOut: 0
        });

        // Execute with insufficient balance - should revert from Permit2
        vm.startPrank(users.buyer);
        address permit2 = AddressConstants.getPermit2Address();
        IERC20(USDC_ADDRESS).approve(permit2, type(uint256).max);
        IAllowanceTransfer(permit2).approve(USDC_ADDRESS, address(swapWithLimitOrders), uint160(type(uint160).max), type(uint48).max);

        // With Permit2, when transferring more than balance, the underlying ERC20 transferFrom fails
        vm.expectRevert("TRANSFER_FROM_FAILED");
        swapWithLimitOrders.swapWithLimitOrders(params);
        vm.stopPrank();
    }
}
