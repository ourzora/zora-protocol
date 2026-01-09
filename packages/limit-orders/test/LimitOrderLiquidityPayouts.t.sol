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
    Currency public lastTakeCurrency;
    uint256 public lastTakeAmount;

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

    function sync(Currency) external {}

    function settle() external payable returns (uint256) {
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
}
