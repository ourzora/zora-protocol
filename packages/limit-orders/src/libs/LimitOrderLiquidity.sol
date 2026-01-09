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

        (bool usePath, IHasSwapPath.PayoutSwapPath memory payoutPath) = _resolvePayoutPath(coinIn, coinLookup);

        (makerCoinOut, makerAmountOut) = _payoutRecipient(poolManager, key, order.maker, makerShareLiquidity0, makerShareLiquidity1, usePath, payoutPath);

        if (referralShareLiquidity0 > 0 || referralShareLiquidity1 > 0) {
            (, referralAmountOut) = _payoutRecipient(poolManager, key, feeRecipient, referralShareLiquidity0, referralShareLiquidity1, usePath, payoutPath);
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

        if (isCurrency0 && amount0 > 0) {
            amountOut = uint128(amount0);
            poolManager.take(key.currency0, recipient, amountOut);
        } else if (!isCurrency0 && amount1 > 0) {
            amountOut = uint128(amount1);
            poolManager.take(key.currency1, recipient, amountOut);
        }

        _settleNegativeDeltas(poolManager, key, amount0, amount1);
    }

    function settleDeltas(IPoolManager poolManager, PoolKey memory key, int256 d0, int256 d1, address payout0, address payout1) internal {
        if (d0 > 0 && payout0 != address(0)) {
            poolManager.take(key.currency0, payout0, uint256(d0));
        }
        if (d0 < 0) {
            poolManager.sync(key.currency0);
            key.currency0.transfer(address(poolManager), uint256(uint256(-d0)));
            poolManager.settle();
        }

        if (d1 > 0 && payout1 != address(0)) {
            poolManager.take(key.currency1, payout1, uint256(d1));
        }
        if (d1 < 0) {
            poolManager.sync(key.currency1);
            key.currency1.transfer(address(poolManager), uint256(uint256(-d1)));
            poolManager.settle();
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
        IDeployedCoinVersionLookup coinLookup
    ) private view returns (bool hasPath, IHasSwapPath.PayoutSwapPath memory payoutPath) {
        if (coinIn == address(0)) {
            return (false, payoutPath);
        }

        try coinLookup.getVersionForDeployedCoin(coinIn) returns (uint8 version) {
            if (version >= 4 && _supportsSwapPath(coinIn)) {
                payoutPath = IHasSwapPath(coinIn).getPayoutSwapPath(coinLookup);
                if (payoutPath.path.length > 0) {
                    return (true, payoutPath);
                }
            }
        } catch {}

        return (false, payoutPath);
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
        PoolKey memory key,
        address recipient,
        int128 amount0,
        int128 amount1,
        bool usePath,
        IHasSwapPath.PayoutSwapPath memory payoutPath
    ) private returns (Currency coinOut, uint128 amountOut) {
        if (usePath) {
            (coinOut, amountOut) = UniV4SwapToCurrency.swapToPath(poolManager, uint128(amount0), uint128(amount1), payoutPath.currencyIn, payoutPath.path);
            poolManager.take(coinOut, recipient, amountOut);
        } else {
            (coinOut, amountOut) = _payCounterAsset(poolManager, key, amount0, amount1, recipient);
        }
    }

    function _payCounterAsset(
        IPoolManager poolManager,
        PoolKey memory key,
        int128 amount0,
        int128 amount1,
        address recipient
    ) private returns (Currency coinOut, uint128 amountOut) {
        if (amount0 > 0) {
            coinOut = key.currency0;
            amountOut = uint128(amount0);
            poolManager.take(coinOut, recipient, amountOut);
        } else if (amount1 > 0) {
            coinOut = key.currency1;
            amountOut = uint128(amount1);
            poolManager.take(coinOut, recipient, amountOut);
        }
    }
}
