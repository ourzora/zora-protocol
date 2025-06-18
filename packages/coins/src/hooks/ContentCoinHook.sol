// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPoolManager, IDeployedCoinVersionLookup, IHasRewardsRecipients, Currency, BaseZoraV4CoinHook} from "./BaseZoraV4CoinHook.sol";
import {CoinRewardsV4} from "../libs/CoinRewardsV4.sol";
import {MarketConstants} from "../libs/MarketConstants.sol";
import {IHooksUpgradeGate} from "../interfaces/IHooksUpgradeGate.sol";

contract ContentCoinHook is BaseZoraV4CoinHook {
    constructor(
        IPoolManager poolManager_,
        IDeployedCoinVersionLookup coinVersionLookup_,
        address[] memory trustedMessageSenders_,
        IHooksUpgradeGate upgradeGate
    ) BaseZoraV4CoinHook(poolManager_, coinVersionLookup_, trustedMessageSenders_, upgradeGate, MarketConstants.POOL_LAUNCH_SUPPLY) {}

    /// @dev Override for market reward distribution
    function _distributeMarketRewards(
        Currency currency,
        uint128 fees,
        IHasRewardsRecipients coin,
        address tradeReferrer
    ) internal override {
        CoinRewardsV4.distributeMarketRewards(currency, fees, coin, tradeReferrer);
    }
}
