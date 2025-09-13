// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ZoraV4CoinHook} from "../../src/hooks/ZoraV4CoinHook.sol";
import {IPoolManager, PoolKey} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IDeployedCoinVersionLookup} from "../../src/interfaces/IDeployedCoinVersionLookup.sol";
import {IHasRewardsRecipients} from "../../src/interfaces/IHasRewardsRecipients.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {CoinCommon} from "../../src/libs/CoinCommon.sol";
import {V4Liquidity} from "../../src/libs/V4Liquidity.sol";
import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {ICoin, IHasSwapPath} from "../../src/interfaces/ICoin.sol";
import {UniV4SwapToCurrency} from "../../src/libs/UniV4SwapToCurrency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CoinRewardsV4} from "../../src/libs/CoinRewardsV4.sol";
import {IHooksUpgradeGate} from "../../src/interfaces/IHooksUpgradeGate.sol";

/// @dev Test util - meant to be able to etched where a normal zora hook is, to gather the fees from swaps but not distribute them
contract FeeEstimatorHook is ZoraV4CoinHook {
    struct FeeEstimatorState {
        uint128 fees0;
        uint128 fees1;
        Currency afterSwapCurrency;
        uint128 afterSwapCurrencyAmount;
        BalanceDelta lastDelta;
        SwapParams lastSwapParams;
        uint256 currencyBalanceChange;
        uint256 coinBalanceChange;
    }

    constructor(
        IPoolManager _poolManager,
        IDeployedCoinVersionLookup _coinVersionLookup,
        IHooksUpgradeGate upgradeGate
    ) ZoraV4CoinHook(_poolManager, _coinVersionLookup, new address[](0), upgradeGate) {}

    FeeEstimatorState public feeState;

    function getFeeState() public view returns (FeeEstimatorState memory) {
        return feeState;
    }

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta _delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        bytes32 poolKeyHash = CoinCommon.hashPoolKey(key);

        // get the coin address and positions for the pool key; they must have been set in the afterInitialize callback
        address coin = poolCoins[poolKeyHash].coin;
        require(coin != address(0), NoCoinForHook(key));

        {
            uint256 coinBalanceBefore = IERC20(coin).balanceOf(address(this));
            uint256 currencyBalanceBefore = IERC20(ICoin(coin).currency()).balanceOf(address(this));

            IHasSwapPath.PayoutSwapPath memory payoutSwapPath = IHasSwapPath(coin).getPayoutSwapPath(coinVersionLookup);

            int128 fee0;
            int128 fee1;

            (fee0, fee1) = V4Liquidity.collectFees(poolManager, key, poolCoins[poolKeyHash].positions);

            (uint128 remainingFee0, uint128 remainingFee1) = CoinRewardsV4.mintLpReward(poolManager, key, fee0, fee1);

            (feeState.afterSwapCurrency, feeState.afterSwapCurrencyAmount) = CoinRewardsV4.convertToPayoutCurrency(
                poolManager,
                remainingFee0,
                remainingFee1,
                payoutSwapPath
            );

            feeState.fees0 += uint128(fee0);
            feeState.fees1 += uint128(fee1);

            uint256 coinBalanceAfter = IERC20(coin).balanceOf(address(this));
            uint256 currencyBalanceAfter = IERC20(ICoin(coin).currency()).balanceOf(address(this));

            feeState.coinBalanceChange = coinBalanceAfter - coinBalanceBefore;
            feeState.currencyBalanceChange = currencyBalanceAfter - currencyBalanceBefore;
        }

        feeState.lastDelta = _delta;
        feeState.lastSwapParams = params;

        return (BaseHook.afterSwap.selector, 0);
    }

    function _distributeMarketRewards(Currency currency, uint128 fees, IHasRewardsRecipients coin, address tradeReferrer) internal override {}
}
