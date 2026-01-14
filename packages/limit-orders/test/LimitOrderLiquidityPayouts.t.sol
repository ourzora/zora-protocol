// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";

import {LimitOrderLiquidity} from "../src/libs/LimitOrderLiquidity.sol";
import {LimitOrderTypes} from "../src/libs/LimitOrderTypes.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {IHasSwapPath} from "@zoralabs/coins/src/interfaces/ICoin.sol";
import {IDeployedCoinVersionLookup} from "@zoralabs/coins/src/interfaces/IDeployedCoinVersionLookup.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {SimpleERC20} from "@zoralabs/coins/test/mocks/SimpleERC20.sol";

contract MockPoolManager {
    using CurrencyLibrary for Currency;

    BalanceDelta private liquidityDelta;
    BalanceDelta private feeDelta;
    BalanceDelta private swapDelta;

    uint256 public swapCalls;
    uint256 public takeCalls;
    uint256 public syncCalls;
    uint256 public settleCalls;
    Currency public lastTakeCurrency;
    uint256 public lastTakeAmount;
    Currency public lastSyncCurrency;
    uint256 public lastSettleValue;

    function setModifyLiquidityResponse(int128 amount0, int128 amount1, int128 fee0, int128 fee1) external {
        liquidityDelta = toBalanceDelta(amount0, amount1);
        feeDelta = toBalanceDelta(fee0, fee1);
    }

    function setSwapResponse(int128 amount0, int128 amount1) external {
        swapDelta = toBalanceDelta(amount0, amount1);
    }

    function modifyLiquidity(PoolKey memory, ModifyLiquidityParams memory, bytes calldata) external returns (BalanceDelta, BalanceDelta) {
        return (liquidityDelta, feeDelta);
    }

    function swap(PoolKey memory, SwapParams memory, bytes calldata) external returns (BalanceDelta) {
        ++swapCalls;
        return swapDelta;
    }

    function take(Currency currency, address to, uint256 amount) external {
        ++takeCalls;
        lastTakeCurrency = currency;
        lastTakeAmount = amount;

        if (currency.isAddressZero()) {
            (bool ok, ) = to.call{value: amount}("");
            require(ok, "native transfer failed");
        } else {
            require(IERC20(Currency.unwrap(currency)).transfer(to, amount), "ERC20 transfer failed");
        }
    }

    function sync(Currency currency) external {
        ++syncCalls;
        lastSyncCurrency = currency;
    }

    function settle() external payable returns (uint256) {
        ++settleCalls;
        lastSettleValue = msg.value;
        return msg.value;
    }

    receive() external payable {}
}

contract LimitOrderLiquidityHarness {
    LimitOrderTypes.LimitOrder internal order;

    function configureOrder(address maker, bool isCurrency0, int24 tickLower, int24 tickUpper, uint128 liquidity) external {
        order.maker = maker;
        order.isCurrency0 = isCurrency0;
        order.tickLower = tickLower;
        order.tickUpper = tickUpper;
        order.liquidity = liquidity;
    }

    function setOrderSide(bool isCurrency0) external {
        order.isCurrency0 = isCurrency0;
    }

    function setOrderMaker(address maker) external {
        order.maker = maker;
    }

    function burnAndPayout(
        MockPoolManager poolManager,
        PoolKey memory key,
        bytes32 orderId,
        address feeRecipient,
        address coinIn,
        IDeployedCoinVersionLookup versionLookup
    ) external returns (Currency coinOut, uint128 makerAmount, uint128 referralAmount) {
        return LimitOrderLiquidity.burnAndPayout(IPoolManager(address(poolManager)), key, order, orderId, feeRecipient, coinIn, versionLookup);
    }

    function burnAndRefund(MockPoolManager poolManager, PoolKey memory key, bytes32 orderId, address recipient) external returns (uint128 amountOut) {
        return
            LimitOrderLiquidity.burnAndRefund(
                IPoolManager(address(poolManager)),
                key,
                order.tickLower,
                order.tickUpper,
                order.liquidity,
                orderId,
                recipient,
                order.isCurrency0
            );
    }

    function refundResidual(PoolKey memory key, bool isCurrency0, address maker, uint128 amount) external {
        LimitOrderLiquidity.refundResidual(key, isCurrency0, maker, amount);
    }
}

contract MockCoinVersionLookup is IDeployedCoinVersionLookup {
    mapping(address => uint8) internal versions;
    bool public forceRevert;

    function setVersion(address coin, uint8 version) external {
        versions[coin] = version;
    }

    function setShouldRevert(bool value) external {
        forceRevert = value;
    }

    function getVersionForDeployedCoin(address coin) external view returns (uint8) {
        if (forceRevert) {
            revert("version lookup revert");
        }
        return versions[coin];
    }
}

contract TestSwapPathCoin is IHasSwapPath, IERC165 {
    Currency internal payoutCurrency;

    constructor(Currency payoutCurrency_) {
        payoutCurrency = payoutCurrency_;
    }

    function getPayoutSwapPath(IDeployedCoinVersionLookup) external view returns (IHasSwapPath.PayoutSwapPath memory payout) {
        payout.currencyIn = Currency.wrap(address(this));
        payout.path = new PathKey[](1);
        payout.path[0] = PathKey({intermediateCurrency: payoutCurrency, fee: 3000, tickSpacing: 60, hooks: IHooks(address(0)), hookData: bytes("")});
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IHasSwapPath).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

contract LimitOrderLiquidityPayoutsTest is Test {
    using CurrencyLibrary for Currency;

    LimitOrderLiquidityHarness internal harness;
    MockPoolManager internal poolManager;
    MockCoinVersionLookup internal versionLookup;
    SimpleERC20 internal currency0Token;
    SimpleERC20 internal currency1Token;
    PoolKey internal poolKey;
    address internal maker;

    bytes32 internal constant ORDER_ID = keccak256("order-id");

    function setUp() public {
        harness = new LimitOrderLiquidityHarness();
        poolManager = new MockPoolManager();
        versionLookup = new MockCoinVersionLookup();

        currency0Token = new SimpleERC20("Token0", "TK0");
        currency1Token = new SimpleERC20("Token1", "TK1");

        poolKey = PoolKey({
            currency0: Currency.wrap(address(currency0Token)),
            currency1: Currency.wrap(address(currency1Token)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        maker = makeAddr("maker");
        harness.configureOrder(maker, true, -120, 120, 1_000);
        versionLookup.setVersion(address(currency0Token), 3); // default to pre-v4 so swap path disabled unless overridden
    }

    function test_refundResidualNativeCurrency() public {
        PoolKey memory nativeKey = PoolKey({
            currency0: CurrencyLibrary.ADDRESS_ZERO,
            currency1: Currency.wrap(address(currency1Token)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        uint128 refundAmount = 1 ether;
        vm.deal(address(harness), refundAmount);

        uint256 makerBalanceBefore = maker.balance;
        harness.refundResidual(nativeKey, true, maker, refundAmount);
        assertEq(maker.balance, makerBalanceBefore + refundAmount, "maker should receive native refund");
    }

    function test_refundResidualErc20Currency() public {
        uint128 refundAmount = 500e18;
        deal(address(currency0Token), address(harness), refundAmount);

        uint256 makerBalanceBefore = currency0Token.balanceOf(maker);
        harness.refundResidual(poolKey, true, maker, refundAmount);
        assertEq(currency0Token.balanceOf(maker), makerBalanceBefore + refundAmount, "maker should receive ERC20 refund");
    }

    function test_refundResidualZeroAmountSkipsTransfer() public {
        uint256 makerBalanceBefore = currency0Token.balanceOf(maker);
        harness.refundResidual(poolKey, true, maker, 0);
        assertEq(currency0Token.balanceOf(maker), makerBalanceBefore, "zero amount should not change balance");
    }

    function test_burnAndRefundPaysCurrency0Orders() public {
        poolManager.setModifyLiquidityResponse(int128(80), 0, 0, 0);
        deal(address(currency0Token), address(poolManager), 100e18);
        address recipient = makeAddr("currency0-recipient");

        uint128 amountOut = harness.burnAndRefund(poolManager, poolKey, ORDER_ID, recipient);
        assertEq(amountOut, 80, "should pay full amount0 delta");
        assertEq(currency0Token.balanceOf(recipient), 80, "recipient receives currency0");
        assertEq(poolManager.takeCalls(), 1, "single take call expected");
        assertEq(Currency.unwrap(poolManager.lastTakeCurrency()), address(currency0Token));
    }

    function test_burnAndRefundPaysCurrency1Orders() public {
        harness.setOrderSide(false);
        poolManager.setModifyLiquidityResponse(0, int128(55), 0, 0);
        deal(address(currency1Token), address(poolManager), 100e18);
        address recipient = makeAddr("currency1-recipient");

        uint128 amountOut = harness.burnAndRefund(poolManager, poolKey, ORDER_ID, recipient);
        assertEq(amountOut, 55, "should pay full amount1 delta");
        assertEq(currency1Token.balanceOf(recipient), 55, "recipient receives currency1");
        assertEq(Currency.unwrap(poolManager.lastTakeCurrency()), address(currency1Token));
    }

    function test_burnAndRefundPaysBothCurrenciesWhenPositive() public {
        poolManager.setModifyLiquidityResponse(int128(10), int128(20), 0, 0);
        deal(address(currency0Token), address(poolManager), 100e18);
        deal(address(currency1Token), address(poolManager), 100e18);
        address recipient = makeAddr("dual-recipient");

        uint128 amountOut = harness.burnAndRefund(poolManager, poolKey, ORDER_ID, recipient);

        assertEq(amountOut, 10, "amountOut should match order currency payout");
        assertEq(currency0Token.balanceOf(recipient), 10, "recipient receives currency0");
        assertEq(currency1Token.balanceOf(recipient), 20, "recipient receives currency1");
        assertEq(poolManager.takeCalls(), 2, "both currencies should be taken");
    }

    function test_burnAndPayoutWithoutReferralRoutesAllProceeds() public {
        poolManager.setModifyLiquidityResponse(0, int128(120), 0, 0);
        deal(address(currency1Token), address(poolManager), 200e18);

        uint256 balanceBefore = currency1Token.balanceOf(maker);
        (, uint128 makerAmount, uint128 referralAmount) = harness.burnAndPayout(
            poolManager,
            poolKey,
            ORDER_ID,
            address(0),
            address(currency0Token),
            versionLookup
        );

        assertEq(makerAmount, 120, "maker payout should match liquidity delta");
        assertEq(referralAmount, 0, "referral should be zero when address(0)");
        assertEq(currency1Token.balanceOf(maker), balanceBefore + 120, "maker receives counter-asset");
        assertEq(poolManager.takeCalls(), 1, "single take call expected");
    }

    function test_burnAndPayoutPaysBothCurrenciesWhenPositive() public {
        // This test now verifies that when both deltas are positive,
        // only ONE currency is paid out (the payout currency) after swapping
        poolManager.setModifyLiquidityResponse(int128(15), int128(25), 0, 0);

        // Simulate swap: 15 of currency0 swaps to get some currency1
        // (mock doesn't track amounts, just that swap occurred)
        poolManager.setSwapResponse(0, int128(0));

        deal(address(currency0Token), address(poolManager), 100e18);
        deal(address(currency1Token), address(poolManager), 100e18);

        uint256 makerCurrency0Before = currency0Token.balanceOf(maker);
        uint256 makerCurrency1Before = currency1Token.balanceOf(maker);

        (, uint128 makerAmount, ) = harness.burnAndPayout(poolManager, poolKey, ORDER_ID, address(0), address(currency0Token), versionLookup);

        // With the fix: only currency1 is paid out (NOT currency0)
        assertEq(currency0Token.balanceOf(maker), makerCurrency0Before, "maker should NOT receive currency0");
        assertGt(currency1Token.balanceOf(maker), makerCurrency1Before, "maker should receive currency1");

        // Verify a swap occurred to convert currency0 to currency1
        assertEq(poolManager.swapCalls(), 1, "swap should occur to consolidate to single currency");
    }

    function test_burnAndPayoutSplitsReferralShares() public {
        poolManager.setModifyLiquidityResponse(0, int128(150), 0, int128(30));
        deal(address(currency1Token), address(poolManager), 300e18);

        address referral = makeAddr("referral");

        uint256 makerBefore = currency1Token.balanceOf(maker);
        uint256 referralBefore = currency1Token.balanceOf(referral);

        (, uint128 makerAmount, uint128 referralAmount) = harness.burnAndPayout(
            poolManager,
            poolKey,
            ORDER_ID,
            referral,
            address(currency0Token),
            versionLookup
        );

        assertEq(makerAmount, 120, "maker receives liquidity minus fees");
        assertEq(referralAmount, 30, "referral receives fee delta");
        assertEq(currency1Token.balanceOf(maker), makerBefore + makerAmount, "maker balance increases");
        assertEq(currency1Token.balanceOf(referral), referralBefore + referralAmount, "referral balance increases");
        assertEq(poolManager.takeCalls(), 2, "maker + referral take calls");
    }

    function test_burnAndPayoutHandlesNativeCoinWithoutSwapPath() public {
        poolManager.setModifyLiquidityResponse(0, int128(90), 0, 0);
        deal(address(currency1Token), address(poolManager), 200e18);

        harness.burnAndPayout(poolManager, poolKey, ORDER_ID, address(0), address(0), versionLookup);

        assertEq(poolManager.swapCalls(), 0, "swap path should not be used for native coin");
    }

    function test_burnAndPayoutFallsBackWhenLookupReverts() public {
        poolManager.setModifyLiquidityResponse(0, int128(75), 0, 0);
        deal(address(currency1Token), address(poolManager), 100e18);
        versionLookup.setShouldRevert(true);

        uint256 balanceBefore = currency1Token.balanceOf(maker);
        harness.burnAndPayout(poolManager, poolKey, ORDER_ID, address(0), address(currency0Token), versionLookup);
        assertEq(currency1Token.balanceOf(maker), balanceBefore + 75, "maker still paid when lookup reverts");
    }

    function test_burnAndPayoutUsesSwapPathWhenAvailable() public {
        TestSwapPathCoin swapCoin = new TestSwapPathCoin(Currency.wrap(address(currency1Token)));
        versionLookup.setVersion(address(swapCoin), 4);

        // Maker has amount0 which must be swapped before payout.
        poolManager.setModifyLiquidityResponse(int128(40), 0, 0, 0);
        poolManager.setSwapResponse(0, int128(40));

        deal(address(currency1Token), address(poolManager), 200e18);

        uint256 makerBefore = currency1Token.balanceOf(maker);

        harness.burnAndPayout(poolManager, poolKey, ORDER_ID, address(0), address(swapCoin), versionLookup);

        assertEq(poolManager.swapCalls(), 1, "swap path should execute");
        assertEq(currency1Token.balanceOf(maker), makerBefore + 40, "maker receives swapped currency");
    }

    /// @notice Test that with dual positive deltas, only currency1 (payout currency) is paid out
    /// @dev This simulates the audit bug scenario where positions have fees in both tokens
    function test_dualPositiveDeltas_payoutsCurrency1Only() public {
        // Order is selling currency0, so payout currency is currency1
        harness.setOrderSide(true); // isCurrency0 = true

        // Simulate dual positive deltas: both amount0 and amount1 are positive
        // This happens when a position is crossed in both directions
        poolManager.setModifyLiquidityResponse(int128(50), int128(100), 0, 0);

        // Simulate swap: swap 50 of currency0 to get 45 of currency1
        poolManager.setSwapResponse(0, int128(45));

        // Fund pool manager with both currencies
        deal(address(currency0Token), address(poolManager), 500e18);
        deal(address(currency1Token), address(poolManager), 500e18);

        uint256 maker0Before = currency0Token.balanceOf(maker);
        uint256 maker1Before = currency1Token.balanceOf(maker);

        (Currency coinOut, uint128 makerAmount, ) = harness.burnAndPayout(poolManager, poolKey, ORDER_ID, address(0), address(0), versionLookup);

        // Verify only currency1 is paid out (NOT currency0)
        assertEq(Currency.unwrap(coinOut), address(currency1Token), "payout currency should be currency1");
        assertEq(currency0Token.balanceOf(maker), maker0Before, "maker should NOT receive currency0");

        // Verify total payout in currency1 includes both the original amount1 + swapped amount0
        // Expected: 100 (original currency1) + 45 (swapped from currency0) = 145
        assertEq(currency1Token.balanceOf(maker), maker1Before + 145, "maker should receive combined amount in currency1");
        assertEq(makerAmount, 145, "makerAmount should be combined total");

        // Verify a swap occurred to convert currency0 to currency1
        assertEq(poolManager.swapCalls(), 1, "swap should occur to convert currency0 to currency1");
    }

    /// @notice Test that with dual positive deltas, only currency0 (payout currency) is paid out
    /// @dev This tests the opposite direction - selling currency1, expecting currency0 payout
    function test_dualPositiveDeltas_payoutsCurrency0Only() public {
        // Order is selling currency1, so payout currency is currency0
        harness.setOrderSide(false); // isCurrency0 = false

        // Simulate dual positive deltas
        poolManager.setModifyLiquidityResponse(int128(80), int128(60), 0, 0);

        // Simulate swap: swap 60 of currency1 to get 55 of currency0
        poolManager.setSwapResponse(int128(55), 0);

        // Fund pool manager
        deal(address(currency0Token), address(poolManager), 500e18);
        deal(address(currency1Token), address(poolManager), 500e18);

        uint256 maker0Before = currency0Token.balanceOf(maker);
        uint256 maker1Before = currency1Token.balanceOf(maker);

        (Currency coinOut, uint128 makerAmount, ) = harness.burnAndPayout(poolManager, poolKey, ORDER_ID, address(0), address(0), versionLookup);

        // Verify only currency0 is paid out (NOT currency1)
        assertEq(Currency.unwrap(coinOut), address(currency0Token), "payout currency should be currency0");
        assertEq(currency1Token.balanceOf(maker), maker1Before, "maker should NOT receive currency1");

        // Verify total payout in currency0 includes both the original amount0 + swapped amount1
        // Expected: 80 (original currency0) + 55 (swapped from currency1) = 135
        assertEq(currency0Token.balanceOf(maker), maker0Before + 135, "maker should receive combined amount in currency0");
        assertEq(makerAmount, 135, "makerAmount should be combined total");

        // Verify a swap occurred
        assertEq(poolManager.swapCalls(), 1, "swap should occur to convert currency1 to currency0");
    }

    /// @notice Test that with dual positive deltas and referral fees, both maker and referral receive single currency
    function test_dualPositiveDeltas_makerAndReferral_singleCurrencyPayout() public {
        address referral = makeAddr("referral");
        harness.setOrderSide(true); // isCurrency0 = true, payout in currency1

        // Simulate dual positive deltas with fees for referral
        // liquidity: (60 amount0, 120 amount1), fees: (20 amount0, 30 amount1)
        poolManager.setModifyLiquidityResponse(int128(60), int128(120), int128(20), int128(30));

        // Simulate swaps for both maker and referral portions
        // First swap (maker): swap 40 of currency0 to get 35 of currency1
        // Second swap (referral): swap 20 of currency0 to get 18 of currency1
        poolManager.setSwapResponse(0, int128(35));

        deal(address(currency0Token), address(poolManager), 500e18);
        deal(address(currency1Token), address(poolManager), 500e18);

        uint256 maker0Before = currency0Token.balanceOf(maker);
        uint256 maker1Before = currency1Token.balanceOf(maker);
        uint256 ref0Before = currency0Token.balanceOf(referral);
        uint256 ref1Before = currency1Token.balanceOf(referral);

        (Currency makerCoinOut, uint128 makerAmount, uint128 referralAmount) = harness.burnAndPayout(
            poolManager,
            poolKey,
            ORDER_ID,
            referral,
            address(0),
            versionLookup
        );

        // Verify maker receives only currency1
        assertEq(Currency.unwrap(makerCoinOut), address(currency1Token), "maker payout should be currency1");
        assertEq(currency0Token.balanceOf(maker), maker0Before, "maker should NOT receive currency0");

        // Verify referral receives only currency1
        assertEq(currency0Token.balanceOf(referral), ref0Before, "referral should NOT receive currency0");

        // Both should have increased currency1 balances
        assertGt(currency1Token.balanceOf(maker), maker1Before, "maker should receive currency1");
        assertGt(currency1Token.balanceOf(referral), ref1Before, "referral should receive currency1");

        // Verify swaps occurred (one for maker, one for referral)
        assertEq(poolManager.swapCalls(), 2, "two swaps should occur (maker + referral)");
    }

    function test_burnAndPayoutBypassesSwapPathWhenPayoutCurrencyMismatches() public {
        TestSwapPathCoin swapCoin = new TestSwapPathCoin(Currency.wrap(address(currency0Token)));
        versionLookup.setVersion(address(swapCoin), 4);

        poolManager.setModifyLiquidityResponse(int128(22), 0, 0, 0);
        poolManager.setSwapResponse(0, int128(22));

        deal(address(currency0Token), address(poolManager), 200e18);
        deal(address(currency1Token), address(poolManager), 200e18);

        uint256 makerBefore = currency1Token.balanceOf(maker);

        harness.burnAndPayout(poolManager, poolKey, ORDER_ID, address(0), address(swapCoin), versionLookup);

        assertEq(poolManager.swapCalls(), 1, "swap should occur using fallback single-hop path");
        assertEq(currency1Token.balanceOf(maker), makerBefore + 22, "maker receives currency1 from swap");
    }
}
