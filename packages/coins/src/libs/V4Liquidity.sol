// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IPoolManager, PoolKey, IHooks, ModifyLiquidityParams, BalanceDelta} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {IHasRewardsRecipients} from "../interfaces/ICoin.sol";
import {IHasSwapPath} from "../interfaces/ICoinV4.sol";
import {UniV4SwapToCurrency} from "./UniV4SwapToCurrency.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";

// command = 1; mint
struct CallbackData {
    uint8 command;
    PoolKey poolKey;
    LpPosition[] positions;
}

struct UnlockData {
    uint256 amount0;
    uint256 amount1;
    int128 fees0;
    int128 fees1;
}

library V4Liquidity {
    using BalanceDeltaLibrary for BalanceDelta;
    using CurrencyLibrary for Currency;

    error CannotMintZeroLiquidity();

    error NegativeFees(int128 amount0, int128 amount1);
    error InvalidCommand(uint8 command);

    function lockAndMint(IPoolManager poolManager, PoolKey memory poolKey, LpPosition[] memory positions) internal {
        bytes memory data = abi.encode(CallbackData({poolKey: poolKey, positions: positions, command: 1}));

        IPoolManager(poolManager).unlock(data);
    }

    function handleCallback(IPoolManager poolManager, bytes memory data) internal returns (UnlockData memory) {
        CallbackData memory callbackData = abi.decode(data, (CallbackData));

        uint256 amount0;
        uint256 amount1;
        int128 fees0;
        int128 fees1;

        if (callbackData.command == 1) {
            (fees0, fees1) = mintPositions(poolManager, callbackData.poolKey, callbackData.positions);
        } else {
            revert InvalidCommand(callbackData.command);
        }

        settleUp(poolManager, callbackData.poolKey);

        return UnlockData({amount0: amount0, amount1: amount1, fees0: fees0, fees1: fees1});
    }

    function collectFees(IPoolManager poolManager, PoolKey memory poolKey, LpPosition[] storage positions) internal returns (int128 balance0, int128 balance1) {
        ModifyLiquidityParams memory params;
        uint256 numPositions = positions.length;

        for (uint256 i; i < numPositions; i++) {
            params = ModifyLiquidityParams({
                tickLower: positions[i].tickLower,
                tickUpper: positions[i].tickUpper,
                liquidityDelta: 0, // only collect
                salt: 0
            });

            (, BalanceDelta feesDelta) = poolManager.modifyLiquidity(poolKey, params, "");

            // check if there is enough erc20 balance for each token to take the fees
            balance0 += feesDelta.amount0();
            balance1 += feesDelta.amount1();
        }
    }

    function swapFullAmount(IPoolManager poolManager, PoolKey memory key, bool zeroForOne, uint128 amountToSwap) internal returns (uint128 amountReceived) {
        if (amountToSwap == 0) {
            return 0;
        }

        SwapParams memory swapParams = SwapParams({
            zeroForOne: zeroForOne,
            // we put in a negative amount to swap, because we want to swap exact amount in
            amountSpecified: -int128(amountToSwap),
            sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
        });

        BalanceDelta swapDelta = poolManager.swap(key, swapParams, "");

        amountReceived = zeroForOne ? uint128(swapDelta.amount1()) : uint128(swapDelta.amount0());
    }

    struct Path {
        PoolKey key;
    }

    // function getSwapPath(PoolKey memory key, Currency toSwapOut) internal view returns (Path[] memory path) {

    // }

    function isCoin(Currency currency) internal view returns (bool) {
        return IERC165(Currency.unwrap(currency)).supportsInterface(type(IHasRewardsRecipients).interfaceId);
    }

    function takeFees(IPoolManager poolManager, Currency currency, uint256 amount) internal {
        if (amount > 0) {
            poolManager.take(currency, address(this), amount);
        }
    }

    function mintPositions(IPoolManager poolManager, PoolKey memory poolKey, LpPosition[] memory positions) internal returns (int128 amount0, int128 amount1) {
        ModifyLiquidityParams memory params;
        uint256 numPositions = positions.length;

        for (uint256 i; i < numPositions; i++) {
            params = ModifyLiquidityParams({
                tickLower: positions[i].tickLower,
                tickUpper: positions[i].tickUpper,
                liquidityDelta: SafeCast.toInt256(positions[i].liquidity),
                salt: 0
            });

            (BalanceDelta delta, ) = poolManager.modifyLiquidity(poolKey, params, "");

            amount0 += delta.amount0();
            amount1 += delta.amount1();
        }
    }

    function settleUp(IPoolManager poolManager, PoolKey memory poolKey) internal returns (int256 currency0Delta, int256 currency1Delta) {
        // calculate the current deltas
        currency0Delta = TransientStateLibrary.currencyDelta(poolManager, address(this), poolKey.currency0);
        currency1Delta = TransientStateLibrary.currencyDelta(poolManager, address(this), poolKey.currency1);

        settleDeltas(poolManager, poolKey, currency0Delta, currency1Delta);
    }

    function settleDeltas(IPoolManager poolManager, PoolKey memory poolKey, int256 currency0Delta, int256 currency1Delta) internal {
        if (currency0Delta > 0) {
            poolManager.take(poolKey.currency0, address(this), uint256(currency0Delta));
        }

        if (currency1Delta > 0) {
            poolManager.take(poolKey.currency1, address(this), uint256(currency1Delta));
        }

        if (currency0Delta < 0) {
            poolManager.sync(poolKey.currency0);
            poolKey.currency0.transfer(address(poolManager), uint256(-currency0Delta));
            poolManager.settle();
        }

        if (currency1Delta < 0) {
            poolManager.sync(poolKey.currency1);
            poolKey.currency1.transfer(address(poolManager), uint256(-currency1Delta));
            poolManager.settle();
        }
    }

    function isCoin(address coin) internal view returns (bool) {
        return IERC165(coin).supportsInterface(type(IHasRewardsRecipients).interfaceId);
    }
}
