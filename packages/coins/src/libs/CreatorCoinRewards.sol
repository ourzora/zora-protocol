// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ICreatorCoinHook} from "../interfaces/ICreatorCoinHook.sol";
import {CoinRewardsV4, IPoolManager, Currency, IHasRewardsRecipients} from "./CoinRewardsV4.sol";

library CreatorCoinRewards {
    function distributeMarketRewards(Currency currency, uint128 fees, IHasRewardsRecipients coin) internal {
        address payoutRecipient = coin.payoutRecipient();
        address protocolRewardRecipient = coin.protocolRewardRecipient();

        uint256 totalAmount = uint256(fees);
        uint256 creatorAmount = CoinRewardsV4.calculateReward(totalAmount, CoinRewardsV4.CREATOR_REWARD_BPS);
        uint256 protocolAmount = totalAmount - creatorAmount;

        CoinRewardsV4._transferCurrency(currency, creatorAmount, payoutRecipient);
        CoinRewardsV4._transferCurrency(currency, protocolAmount, protocolRewardRecipient);

        emit ICreatorCoinHook.CreatorCoinRewards(
            address(coin),
            Currency.unwrap(currency),
            payoutRecipient,
            protocolRewardRecipient,
            creatorAmount,
            protocolAmount
        );
    }
}
