// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.28;

import {IPoolManager, IDeployedCoinVersionLookup, IHasRewardsRecipients, Currency, BaseZoraV4CoinHook} from "./BaseZoraV4CoinHook.sol";
import {CoinRewardsV4} from "../libs/CoinRewardsV4.sol";
import {CoinConstants} from "../libs/CoinConstants.sol";
import {IHooksUpgradeGate} from "../interfaces/IHooksUpgradeGate.sol";

contract ContentCoinHook is BaseZoraV4CoinHook {
    constructor(
        IPoolManager poolManager_,
        IDeployedCoinVersionLookup coinVersionLookup_,
        address[] memory trustedMessageSenders_,
        IHooksUpgradeGate upgradeGate
    ) BaseZoraV4CoinHook(poolManager_, coinVersionLookup_, trustedMessageSenders_, upgradeGate, CoinConstants.POOL_LAUNCH_SUPPLY) {}

    /// @dev Override for market reward distribution
    function _distributeMarketRewards(Currency currency, uint128 fees, IHasRewardsRecipients coin, address tradeReferrer) internal override {
        CoinRewardsV4.distributeMarketRewards(currency, fees, coin, tradeReferrer);
    }
}
