// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ZoraV4CoinHook} from "../../src/hooks/ZoraV4CoinHook.sol";
import {IPoolManager, PoolKey} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHasRewardsRecipients} from "../../src/interfaces/ICoin.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {CoinCommon} from "../../src/libs/CoinCommon.sol";
import {V4Liquidity} from "../../src/libs/V4Liquidity.sol";
import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";

/// @dev Test util - meant to be able to etched where a normal zora hook is, to gather the fees from swaps but not distribute them
contract FeeEstimatorHook is ZoraV4CoinHook {
    constructor(IPoolManager _poolManager) ZoraV4CoinHook(_poolManager, new address[](0)) {}

    uint128 public fees0;
    uint128 public fees1;
    BalanceDelta public lastDelta;
    SwapParams public _lastSwapParams;

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta _delta,
        bytes calldata hookData
    ) internal override returns (bytes4, int128) {
        bytes32 poolKeyHash = CoinCommon.hashPoolKey(key);

        // get the coin address and positions for the pool key; they must have been set in the afterInitialize callback
        address coin = poolCoins[poolKeyHash].coin;
        require(coin != address(0), NoCoinForHook(key));

        {
            (int128 fee0, int128 fee1) = V4Liquidity.collectAndTakeFees(poolManager, key, poolCoins[poolKeyHash].positions);

            fees0 += uint128(fee0);
            fees1 += uint128(fee1);
        }

        lastDelta = _delta;
        _lastSwapParams = params;

        return (BaseHook.afterSwap.selector, 0);
    }

    function lastSwapParams() public view returns (SwapParams memory) {
        return _lastSwapParams;
    }
}
