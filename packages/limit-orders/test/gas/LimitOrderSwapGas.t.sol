// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseTest} from "../utils/BaseTest.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LimitOrderCommon} from "../../src/libs/LimitOrderCommon.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SwapWithLimitOrders} from "../../src/router/SwapWithLimitOrders.sol";
import {AddressConstants} from "@zoralabs/coins/test/utils/hookmate/constants/AddressConstants.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

/**
 * @title LimitOrderSwapGasTest
 * @notice Forked gas benchmarks for a single swap that fills existing orders and creates 5 new ones.
 */
contract LimitOrderSwapGasTest is BaseTest {
    uint256 internal constant FORK_BLOCK = 38_875_958;
    uint256 internal constant DEFAULT_MAX_FILL_COUNT = 50;

    uint256 private gasStart;
    uint256 private gasUsed;

    function setUp() public override {
        setUpWithBlockNumber(FORK_BLOCK);
        limitOrderBook.setMaxFillCount(DEFAULT_MAX_FILL_COUNT);
    }

    function test_gas_hop2_swap_create5_fill5() public {
        _runHop2Swap(5);
    }

    function test_gas_hop2_swap_create5_fill10() public {
        _runHop2Swap(10);
    }

    function test_gas_hop2_swap_create5_fill25() public {
        _runHop2Swap(25);
    }

    function test_gas_hop2_swap_create5_fill50() public {
        _runHop2Swap(50);
    }

    function test_gas_hop3_swap_create5_fill5() public {
        _runHop3Swap(5);
    }

    function test_gas_hop3_swap_create5_fill10() public {
        _runHop3Swap(10);
    }

    function test_gas_hop3_swap_create5_fill25() public {
        _runHop3Swap(25);
    }

    function test_gas_hop3_swap_create5_fill50() public {
        _runHop3Swap(50);
    }

    function test_gas_hop4_swap_create5_fill5() public {
        _runHop4Swap(5);
    }

    function test_gas_hop4_swap_create5_fill10() public {
        _runHop4Swap(10);
    }

    function test_gas_hop4_swap_create5_fill25() public {
        _runHop4Swap(25);
    }

    function test_gas_hop4_swap_create5_fill50() public {
        _runHop4Swap(50);
    }

    function test_gas_hop1_swap_create5_fill5() public {
        _runHop1Swap(5);
    }

    function test_gas_hop1_swap_create5_fill10() public {
        _runHop1Swap(10);
    }

    function test_gas_hop1_swap_create5_fill25() public {
        _runHop1Swap(25);
    }

    function test_gas_hop1_swap_create5_fill50() public {
        _runHop1Swap(50);
    }

    function test_gas_hop3_swap_create5_fill0() public {
        _runHop3NoFill();
    }

    function test_gas_hop4_swap_create5_fill0() public {
        _runHop4NoFill();
    }

    // ---------------- helpers ----------------

    function _runHop1Swap(uint256 existingOrders) internal {
        PoolKey memory creatorKey = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(creatorKey.currency0) == address(creatorCoin);

        CreatedOrderLog[] memory preloaded = existingOrders > 0 ? _preloadOrders(creatorKey, isCurrency0, existingOrders) : new CreatedOrderLog[](0);
        emit log_named_uint("PRELOADED_ORDERS", preloaded.length);

        vm.prank(users.factoryOwner);
        limitOrderBook.setMaxFillCount(existingOrders + 10);

        PoolKey[] memory v4Route = new PoolKey[](1);
        v4Route[0] = creatorKey;
        bytes memory v3Route = bytes("");

        uint256 amountIn = 1_000e18;
        _fundAndApprove(address(zoraToken), amountIn, users.buyer);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = SwapWithLimitOrders.SwapWithLimitOrdersParams({
            recipient: users.buyer,
            limitOrderConfig: _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages()),
            inputCurrency: address(zoraToken),
            inputAmount: amountIn,
            v3Route: v3Route,
            v4Route: v4Route,
            minAmountOut: 0
        });

        vm.recordLogs();
        gasStart = gasleft();
        vm.prank(users.buyer);
        swapWithLimitOrders.swapWithLimitOrders(params);
        gasUsed = gasStart - gasleft();

        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());

        emit log_named_uint("ROUTER_CREATED_ORDERS", created.length);
        emit log_named_uint("SWAP_FILLED_ORDERS", fills.length);
        emit log_named_uint("SINGLE_SWAP_CREATE_AND_FILL_GAS", gasUsed);

        address orderCoin = LimitOrderCommon.getOrderCoin(creatorKey, isCurrency0);
        emit log_named_uint("MAKER_BALANCE_AFTER", limitOrderBook.balanceOf(users.buyer, orderCoin));
    }

    function _runHop2Swap(uint256 existingOrders) internal {
        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);

        CreatedOrderLog[] memory preloaded = existingOrders > 0 ? _preloadOrders(contentKey, isCurrency0, existingOrders) : new CreatedOrderLog[](0);
        emit log_named_uint("PRELOADED_ORDERS", preloaded.length);

        // allow enough fills (existing + some headroom for newly in-range orders)
        vm.prank(users.factoryOwner);
        limitOrderBook.setMaxFillCount(existingOrders + 10);

        // build router params (hop2: ZORA -> creator -> content)
        PoolKey[] memory v4Route = new PoolKey[](2);
        v4Route[0] = creatorCoin.getPoolKey();
        v4Route[1] = contentCoin.getPoolKey();
        bytes memory v3Route = bytes("");

        uint256 amountIn = 1_000e18; // large enough to cross ticks
        _fundAndApprove(address(zoraToken), amountIn, users.buyer);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = SwapWithLimitOrders.SwapWithLimitOrdersParams({
            recipient: users.buyer,
            limitOrderConfig: _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages()),
            inputCurrency: address(zoraToken),
            inputAmount: amountIn,
            v3Route: v3Route,
            v4Route: v4Route,
            minAmountOut: 0
        });

        vm.recordLogs();
        gasStart = gasleft();
        vm.prank(users.buyer);
        swapWithLimitOrders.swapWithLimitOrders(params);
        gasUsed = gasStart - gasleft();

        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());

        emit log_named_uint("ROUTER_CREATED_ORDERS", created.length);
        emit log_named_uint("SWAP_FILLED_ORDERS", fills.length);
        emit log_named_uint("SINGLE_SWAP_CREATE_AND_FILL_GAS", gasUsed);

        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);
        emit log_named_uint("MAKER_BALANCE_AFTER", limitOrderBook.balanceOf(users.buyer, orderCoin));
    }

    function _runHop3Swap(uint256 existingOrders) internal {
        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);

        CreatedOrderLog[] memory preloaded = existingOrders > 0 ? _preloadOrders(contentKey, isCurrency0, existingOrders) : new CreatedOrderLog[](0);
        emit log_named_uint("PRELOADED_ORDERS", preloaded.length);

        vm.prank(users.factoryOwner);
        limitOrderBook.setMaxFillCount(existingOrders + 10);

        PoolKey[] memory v4Route = new PoolKey[](2);
        v4Route[0] = creatorCoin.getPoolKey();
        v4Route[1] = contentCoin.getPoolKey();
        bytes memory v3Route = abi.encodePacked(USDC_ADDRESS, uint24(10000), ZORA_TOKEN_ADDRESS);

        uint256 amountIn = 20_000e6;
        _fundAndApprove(USDC_ADDRESS, amountIn, users.buyer);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = SwapWithLimitOrders.SwapWithLimitOrdersParams({
            recipient: users.buyer,
            limitOrderConfig: _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages()),
            inputCurrency: USDC_ADDRESS,
            inputAmount: amountIn,
            v3Route: v3Route,
            v4Route: v4Route,
            minAmountOut: 0
        });

        vm.recordLogs();
        gasStart = gasleft();
        vm.prank(users.buyer);
        swapWithLimitOrders.swapWithLimitOrders(params);
        gasUsed = gasStart - gasleft();

        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());

        emit log_named_uint("ROUTER_CREATED_ORDERS", created.length);
        emit log_named_uint("SWAP_FILLED_ORDERS", fills.length);
        emit log_named_uint("SINGLE_SWAP_CREATE_AND_FILL_GAS", gasUsed);

        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);
        emit log_named_uint("MAKER_BALANCE_AFTER", limitOrderBook.balanceOf(users.buyer, orderCoin));
    }

    function _runHop4Swap(uint256 existingOrders) internal {
        PoolKey memory contentKey = contentCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(contentKey.currency0) == address(contentCoin);

        CreatedOrderLog[] memory preloaded = existingOrders > 0 ? _preloadOrders(contentKey, isCurrency0, existingOrders) : new CreatedOrderLog[](0);
        emit log_named_uint("PRELOADED_ORDERS", preloaded.length);

        vm.prank(users.factoryOwner);
        limitOrderBook.setMaxFillCount(existingOrders + 10);

        PoolKey[] memory v4Route = new PoolKey[](2);
        v4Route[0] = creatorCoin.getPoolKey();
        v4Route[1] = contentCoin.getPoolKey();
        bytes memory v3Route = abi.encodePacked(WETH_ADDRESS, uint24(500), USDC_ADDRESS, uint24(10000), ZORA_TOKEN_ADDRESS);

        uint256 amountIn = 10 ether;
        _fundAndApprove(WETH_ADDRESS, amountIn, users.buyer);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = SwapWithLimitOrders.SwapWithLimitOrdersParams({
            recipient: users.buyer,
            limitOrderConfig: _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages()),
            inputCurrency: WETH_ADDRESS,
            inputAmount: amountIn,
            v3Route: v3Route,
            v4Route: v4Route,
            minAmountOut: 0
        });

        vm.recordLogs();
        gasStart = gasleft();
        vm.prank(users.buyer);
        swapWithLimitOrders.swapWithLimitOrders(params);
        gasUsed = gasStart - gasleft();

        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());

        emit log_named_uint("ROUTER_CREATED_ORDERS", created.length);
        emit log_named_uint("SWAP_FILLED_ORDERS", fills.length);
        emit log_named_uint("SINGLE_SWAP_CREATE_AND_FILL_GAS", gasUsed);

        address orderCoin = LimitOrderCommon.getOrderCoin(contentKey, isCurrency0);
        emit log_named_uint("MAKER_BALANCE_AFTER", limitOrderBook.balanceOf(users.buyer, orderCoin));
    }

    function _runHop3NoFill() internal {
        PoolKey memory creatorKey = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(creatorKey.currency0) == address(creatorCoin);

        vm.prank(users.factoryOwner);
        limitOrderBook.setMaxFillCount(10);

        PoolKey[] memory v4Route = new PoolKey[](1);
        v4Route[0] = creatorKey;
        bytes memory v3Route = abi.encodePacked(USDC_ADDRESS, uint24(10000), ZORA_TOKEN_ADDRESS);

        uint256 amountIn = 10_000e6;
        _fundAndApprove(USDC_ADDRESS, amountIn, users.buyer);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = SwapWithLimitOrders.SwapWithLimitOrdersParams({
            recipient: users.buyer,
            limitOrderConfig: _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages()),
            inputCurrency: USDC_ADDRESS,
            inputAmount: amountIn,
            v3Route: v3Route,
            v4Route: v4Route,
            minAmountOut: 0
        });

        vm.recordLogs();
        gasStart = gasleft();
        vm.prank(users.buyer);
        swapWithLimitOrders.swapWithLimitOrders(params);
        gasUsed = gasStart - gasleft();

        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());

        emit log_named_uint("ROUTER_CREATED_ORDERS", created.length);
        emit log_named_uint("SWAP_FILLED_ORDERS", fills.length);
        emit log_named_uint("SINGLE_SWAP_CREATE_AND_FILL_GAS", gasUsed);

        address orderCoin = LimitOrderCommon.getOrderCoin(creatorKey, isCurrency0);
        emit log_named_uint("MAKER_BALANCE_AFTER", limitOrderBook.balanceOf(users.buyer, orderCoin));
    }

    function _runHop4NoFill() internal {
        PoolKey memory creatorKey = creatorCoin.getPoolKey();
        bool isCurrency0 = Currency.unwrap(creatorKey.currency0) == address(creatorCoin);

        vm.prank(users.factoryOwner);
        limitOrderBook.setMaxFillCount(10);

        PoolKey[] memory v4Route = new PoolKey[](1);
        v4Route[0] = creatorKey;
        bytes memory v3Route = abi.encodePacked(WETH_ADDRESS, uint24(500), USDC_ADDRESS, uint24(10000), ZORA_TOKEN_ADDRESS);

        uint256 amountIn = 5 ether;
        _fundAndApprove(WETH_ADDRESS, amountIn, users.buyer);

        SwapWithLimitOrders.SwapWithLimitOrdersParams memory params = SwapWithLimitOrders.SwapWithLimitOrdersParams({
            recipient: users.buyer,
            limitOrderConfig: _prepareLimitOrderParams(users.buyer, _defaultMultiples(), _defaultPercentages()),
            inputCurrency: WETH_ADDRESS,
            inputAmount: amountIn,
            v3Route: v3Route,
            v4Route: v4Route,
            minAmountOut: 0
        });

        vm.recordLogs();
        gasStart = gasleft();
        vm.prank(users.buyer);
        swapWithLimitOrders.swapWithLimitOrders(params);
        gasUsed = gasStart - gasleft();

        FilledOrderLog[] memory fills = _decodeFilledLogs(vm.getRecordedLogs());
        CreatedOrderLog[] memory created = _decodeCreatedLogs(vm.getRecordedLogs());

        emit log_named_uint("ROUTER_CREATED_ORDERS", created.length);
        emit log_named_uint("SWAP_FILLED_ORDERS", fills.length);
        emit log_named_uint("SINGLE_SWAP_CREATE_AND_FILL_GAS", gasUsed);

        address orderCoin = LimitOrderCommon.getOrderCoin(creatorKey, isCurrency0);
        emit log_named_uint("MAKER_BALANCE_AFTER", limitOrderBook.balanceOf(users.buyer, orderCoin));
    }

    function _fundAndApprove(address token, uint256 amount, address trader) internal {
        if (token == address(0)) {
            vm.deal(trader, amount);
            return;
        }
        deal(token, trader, amount);
        address permit2 = AddressConstants.getPermit2Address();
        vm.startPrank(trader);
        IERC20(token).approve(permit2, type(uint256).max);
        IAllowanceTransfer(permit2).approve(token, address(swapWithLimitOrders), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function _preloadOrders(PoolKey memory key, bool isCurrency0, uint256 count) internal returns (CreatedOrderLog[] memory created) {
        address orderCoin = LimitOrderCommon.getOrderCoin(key, isCurrency0);

        uint256 orderSize = 25e18;
        (uint256[] memory sizes, int24[] memory ticks) = _buildDeterministicOrders(key, isCurrency0, count, orderSize);

        uint256 totalSize;
        for (uint256 i; i < sizes.length; ++i) {
            totalSize += sizes[i];
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
        limitOrderBook.create{value: orderCoin == address(0) ? totalSize : 0}(key, isCurrency0, sizes, ticks, users.seller);
        created = _decodeCreatedLogs(vm.getRecordedLogs());
    }
}
