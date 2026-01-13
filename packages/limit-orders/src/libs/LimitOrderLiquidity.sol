// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {LiquidityAmounts} from "@zoralabs/coins/src/utils/uniswap/LiquidityAmounts.sol";

import {IDeployedCoinVersionLookup} from "@zoralabs/coins/src/interfaces/IDeployedCoinVersionLookup.sol";
import {LimitOrderTypes} from "./LimitOrderTypes.sol";
import {IHasSwapPath} from "@zoralabs/coins/src/interfaces/ICoin.sol";
import {UniV4SwapToCurrency} from "@zoralabs/coins/src/libs/UniV4SwapToCurrency.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";

library LimitOrderLiquidity {
    using CurrencyLibrary for Currency;

    function liquidityForOrder(bool isCurrency0, uint256 size, int24 tickLower, int24 tickUpper) internal pure returns (uint128) {
        uint160 sqrtPriceLower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceUpper = TickMath.getSqrtPriceAtTick(tickUpper);
        return
            isCurrency0
                ? LiquidityAmounts.getLiquidityForAmount0(sqrtPriceLower, sqrtPriceUpper, size)
                : LiquidityAmounts.getLiquidityForAmount1(sqrtPriceLower, sqrtPriceUpper, size);
    }

    function refundResidual(PoolKey memory key, bool isCurrency0, address maker, uint128 amount) internal {
        if (amount == 0) {
            return;
        }
        Currency currency = isCurrency0 ? key.currency0 : key.currency1;
        currency.transfer(maker, amount);
    }

    function settleAfterCreate(IPoolManager poolManager, PoolKey memory key, bool isCurrency0) internal {
        int256 delta0 = TransientStateLibrary.currencyDelta(poolManager, address(this), key.currency0);
        int256 delta1 = TransientStateLibrary.currencyDelta(poolManager, address(this), key.currency1);

        address payout0 = isCurrency0 ? address(0) : address(this);
        address payout1 = isCurrency0 ? address(this) : address(0);

        settleDeltas(poolManager, key, delta0, delta1, payout0, payout1);
    }

    function burnAndPayout(
        IPoolManager poolManager,
        PoolKey memory key,
        LimitOrderTypes.LimitOrder storage order,
        bytes32 orderId,
        address feeRecipient,
        address coinIn,
        IDeployedCoinVersionLookup coinLookup
    ) internal returns (Currency makerCoinOut, uint128 makerAmountOut, uint128 referralAmountOut) {
        (BalanceDelta liqDelta, BalanceDelta feesDelta) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: order.tickLower, tickUpper: order.tickUpper, liquidityDelta: -int256(uint256(order.liquidity)), salt: orderId}),
            ""
        );

        int128 liquidity0 = liqDelta.amount0();
        int128 liquidity1 = liqDelta.amount1();
        int128 fee0Initial = feesDelta.amount0();
        int128 fee1Initial = feesDelta.amount1();

        int128 makerShareLiquidity0 = feeRecipient == address(0) ? liquidity0 : liquidity0 - fee0Initial;
        int128 makerShareLiquidity1 = feeRecipient == address(0) ? liquidity1 : liquidity1 - fee1Initial;
        int128 referralShareLiquidity0 = feeRecipient == address(0) ? int128(0) : int128(fee0Initial);
        int128 referralShareLiquidity1 = feeRecipient == address(0) ? int128(0) : int128(fee1Initial);

        Currency payoutCurrency = order.isCurrency0 ? key.currency1 : key.currency0;
        IHasSwapPath.PayoutSwapPath memory payoutPath = _resolvePayoutPath(coinIn, coinLookup, key, payoutCurrency);

        (makerCoinOut, makerAmountOut) = _payoutRecipient(poolManager, order.maker, makerShareLiquidity0, makerShareLiquidity1, payoutPath);

        if (referralShareLiquidity0 > 0 || referralShareLiquidity1 > 0) {
            (, referralAmountOut) = _payoutRecipient(poolManager, feeRecipient, referralShareLiquidity0, referralShareLiquidity1, payoutPath);
        }

        _settleNegativeDeltas(poolManager, key, liquidity0 + fee0Initial, liquidity1 + fee1Initial);
    }

    function burnAndRefund(
        IPoolManager poolManager,
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        bytes32 salt,
        address recipient,
        bool isCurrency0
    ) internal returns (uint128 amountOut) {
        (int128 amount0, int128 amount1) = _burnLiquidity(poolManager, key, tickLower, tickUpper, liquidity, salt);

        if (amount0 > 0) {
            uint128 amount0Out = uint128(amount0);
            poolManager.take(key.currency0, recipient, amount0Out);
            if (isCurrency0) {
                amountOut = amount0Out;
            }
        }
        if (amount1 > 0) {
            uint128 amount1Out = uint128(amount1);
            poolManager.take(key.currency1, recipient, amount1Out);
            if (!isCurrency0) {
                amountOut = amount1Out;
            }
        }

        _settleNegativeDeltas(poolManager, key, amount0, amount1);
    }

    function settleDeltas(IPoolManager poolManager, PoolKey memory key, int256 d0, int256 d1, address payout0, address payout1) internal {
        if (d0 > 0 && payout0 != address(0)) {
            poolManager.take(key.currency0, payout0, uint256(d0));
        }
        if (d0 < 0) {
            uint256 amount = uint256(uint256(-d0));
            poolManager.sync(key.currency0);
            if (key.currency0.isAddressZero()) {
                poolManager.settle{value: amount}();
            } else {
                key.currency0.transfer(address(poolManager), amount);
                poolManager.settle();
            }
        }

        if (d1 > 0 && payout1 != address(0)) {
            poolManager.take(key.currency1, payout1, uint256(d1));
        }
        if (d1 < 0) {
            uint256 amount = uint256(uint256(-d1));
            poolManager.sync(key.currency1);
            if (key.currency1.isAddressZero()) {
                poolManager.settle{value: amount}();
            } else {
                key.currency1.transfer(address(poolManager), amount);
                poolManager.settle();
            }
        }
    }

    function _burnLiquidity(
        IPoolManager poolManager,
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        bytes32 salt
    ) private returns (int128 amount0, int128 amount1) {
        (BalanceDelta delta, ) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: tickLower, tickUpper: tickUpper, liquidityDelta: -int256(uint256(liquidity)), salt: salt}),
            ""
        );
        amount0 = delta.amount0();
        amount1 = delta.amount1();
    }

    function _resolvePayoutPath(
        address coinIn,
        IDeployedCoinVersionLookup coinLookup,
        PoolKey memory key,
        Currency payoutCurrency
    ) private view returns (IHasSwapPath.PayoutSwapPath memory payoutPath) {
        // Try to get multi-hop path from coin
        if (coinIn != address(0)) {
            try coinLookup.getVersionForDeployedCoin(coinIn) returns (uint8 version) {
                if (version >= 4 && _supportsSwapPath(coinIn)) {
                    payoutPath = IHasSwapPath(coinIn).getPayoutSwapPath(coinLookup);
                    // Validate first hop matches expected payout currency
                    if (payoutPath.path.length > 0 && payoutPath.path[0].intermediateCurrency == payoutCurrency) {
                        return payoutPath;
                    }
                }
            } catch {}
        }

        // Fallback: construct simple single-hop path
        Currency coinCurrency = payoutCurrency == key.currency0 ? key.currency1 : key.currency0;
        payoutPath.currencyIn = coinCurrency;
        payoutPath.path = new PathKey[](1);
        payoutPath.path[0] = PathKey({intermediateCurrency: payoutCurrency, fee: key.fee, tickSpacing: key.tickSpacing, hooks: key.hooks, hookData: bytes("")});
    }

    function _supportsSwapPath(address coin) private view returns (bool) {
        try IERC165(coin).supportsInterface(type(IHasSwapPath).interfaceId) returns (bool supported) {
            return supported;
        } catch {
            return false;
        }
    }

    function _settleNegativeDeltas(IPoolManager poolManager, PoolKey memory key, int128 amount0, int128 amount1) private {
        int256 repay0 = amount0 < 0 ? int256(amount0) : int256(0);
        int256 repay1 = amount1 < 0 ? int256(amount1) : int256(0);

        if (repay0 != 0 || repay1 != 0) {
            settleDeltas(poolManager, key, repay0, repay1, address(0), address(0));
        }
    }

    function _payoutRecipient(
        IPoolManager poolManager,
        address recipient,
        int128 amount0,
        int128 amount1,
        IHasSwapPath.PayoutSwapPath memory payoutPath
    ) private returns (Currency coinOut, uint128 amountOut) {
        // Convert to uint128, treating negative/zero as zero
        uint128 amt0 = amount0 > 0 ? uint128(amount0) : 0;
        uint128 amt1 = amount1 > 0 ? uint128(amount1) : 0;

        // Use swapToPath which handles all cases:
        // - Single positive delta: returns that currency
        // - Dual positive deltas: swaps one to the other and returns combined amount
        // - Multi-hop paths: handles coin -> backingCoin -> backingCoin's currency
        (coinOut, amountOut) = UniV4SwapToCurrency.swapToPath(poolManager, amt0, amt1, payoutPath.currencyIn, payoutPath.path);

        if (amountOut > 0) {
            poolManager.take(coinOut, recipient, amountOut);
        }
    }
}
