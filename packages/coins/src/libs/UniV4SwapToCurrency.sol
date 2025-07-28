// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {ISwapPathRouter} from "../interfaces/ISwapPathRouter.sol";
import {IHasPoolKey} from "../interfaces/ICoin.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IPoolManager, PoolKey} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IHasSwapPath} from "../interfaces/ICoin.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {IDeployedCoinVersionLookup} from "../interfaces/IDeployedCoinVersionLookup.sol";
import {IZoraV4CoinHook} from "../interfaces/IZoraV4CoinHook.sol";
import {CoinConfigurationVersions} from "./CoinConfigurationVersions.sol";

library UniV4SwapToCurrency {
    using BalanceDeltaLibrary for BalanceDelta;

    function swapToPath(
        IPoolManager poolManager,
        uint128 amount0,
        uint128 amount1,
        Currency currencyIn,
        PathKey[] memory path
    ) internal returns (Currency lastCurrency, uint128 lastCurrencyBalance) {
        require(path.length > 0, IZoraV4CoinHook.PathMustHaveAtLeastOneStep());

        // do first swap - the first swap updates output the balance with the initial balance that existed before the swap
        (lastCurrency, lastCurrencyBalance) = doFirstSwapFromCoinToCurrency(poolManager, path[0], currencyIn, amount0, amount1);

        // for each path, swap the currency to the next currency
        for (uint256 i = 1; i < path.length; i++) {
            (PoolKey memory poolKey, bool zeroForOne) = _getPoolAndSwapDirection(path[i], lastCurrency);
            lastCurrencyBalance = uint128(_swap(poolManager, poolKey, zeroForOne, -int128(lastCurrencyBalance), ""));
            lastCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;
        }
    }

    function doFirstSwapFromCoinToCurrency(
        IPoolManager poolManager,
        PathKey memory pathKey,
        Currency coin,
        uint128 amount0,
        uint128 amount1
    ) internal returns (Currency outputCurrency, uint128 outputAmount) {
        (PoolKey memory poolKey, bool zeroForOne) = _getPoolAndSwapDirection(pathKey, coin);

        uint128 inputAmount = zeroForOne ? amount0 : amount1;

        outputCurrency = zeroForOne ? poolKey.currency1 : poolKey.currency0;

        uint128 initialAmountCurrency = zeroForOne ? amount1 : amount0;

        // if not swapping any coin for currency, output amount is amount of currency
        if (inputAmount == 0) {
            outputAmount = initialAmountCurrency;
        } else {
            outputAmount = initialAmountCurrency + uint128(_swap(poolManager, poolKey, zeroForOne, -int128(inputAmount), bytes("")));
        }
    }

    function _swap(
        IPoolManager poolManager,
        PoolKey memory poolKey,
        bool zeroForOne,
        int256 amountSpecified,
        bytes memory hookData
    ) private returns (int128 reciprocalAmount) {
        // for protection of exactOut swaps, sqrtPriceLimit is not exposed as a feature in this contract
        unchecked {
            BalanceDelta delta = poolManager.swap(
                poolKey,
                SwapParams(zeroForOne, amountSpecified, zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1),
                hookData
            );

            reciprocalAmount = (zeroForOne == amountSpecified < 0) ? delta.amount1() : delta.amount0();
        }
    }

    /// @notice Get the pool and swap direction for a given PathKey
    /// @param params the given PathKey
    /// @param currencyIn the input currency
    /// @return poolKey the pool key of the swap
    /// @return zeroForOne the direction of the swap, true if currency0 is being swapped for currency1
    function _getPoolAndSwapDirection(PathKey memory params, Currency currencyIn) internal pure returns (PoolKey memory poolKey, bool zeroForOne) {
        Currency currencyOut = params.intermediateCurrency;
        (Currency currency0, Currency currency1) = currencyIn < currencyOut ? (currencyIn, currencyOut) : (currencyOut, currencyIn);

        zeroForOne = currencyIn == currency0;
        poolKey = PoolKey(currency0, currency1, params.fee, params.tickSpacing, params.hooks);
    }

    function getSubSwapPath(address currency, IDeployedCoinVersionLookup coinVersionLookup) internal view returns (PathKey[] memory) {
        if (!_hasSwapPath(currency, coinVersionLookup)) {
            return new PathKey[](0);
        }
        return IHasSwapPath(currency).getPayoutSwapPath(coinVersionLookup).path;
    }

    function _hasSwapPath(address currency, IDeployedCoinVersionLookup coinVersionLookup) private view returns (bool) {
        if (CoinConfigurationVersions.isV4(coinVersionLookup.getVersionForDeployedCoin(currency))) {
            return IERC165(currency).supportsInterface(type(IHasSwapPath).interfaceId);
        }
        return false;
    }
}
