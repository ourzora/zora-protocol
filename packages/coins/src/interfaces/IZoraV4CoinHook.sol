// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ICoin} from "./ICoin.sol";

interface IZoraV4CoinHook {
    event Swapped(
        address indexed sender,
        address indexed swapSender,
        bool isTrustedSwapSenderAddress,
        PoolKey key,
        bytes32 indexed poolKeyHash,
        SwapParams params,
        int128 amount0,
        int128 amount1,
        bool isCoinBuy,
        bytes hookData
    );

    /// Thrown when a non-coin is used to initialize a pool with this hook.
    error NotACoin(address coin);

    error NoCoinForHook(PoolKey key);

    /// @notice The rewards accrued from the market's liquidity position
    /// @param creatorPayoutAmountCurrency The amount of currency payed out to the creator
    /// @param creatorPayoutAmountCoin The amount of coin payed out to the creator
    /// @param platformReferrerAmountCurrency The amount of currency payed out to the platform referrer
    /// @param platformReferrerAmountCoin The amount of coin payed out to the platform referrer
    /// @param tradeReferrerAmountCurrency The amount of currency payed out to the trade referrer
    /// @param tradeReferrerAmountCoin The amount of coin to pay to the trade referrer
    /// @param protocolAmountCurrency The amount of currency to pay to the protocol
    /// @param protocolAmountCoin The amount of coin to pay to the protocol
    /// @param dopplerAmountCurrency The amount of currency to pay to doppler
    /// @param dopplerAmountCoin The amount of coin to pay to doppler
    struct MarketRewardsV4 {
        uint256 creatorPayoutAmountCurrency;
        uint256 creatorPayoutAmountCoin;
        uint256 platformReferrerAmountCurrency;
        uint256 platformReferrerAmountCoin;
        uint256 tradeReferrerAmountCurrency;
        uint256 tradeReferrerAmountCoin;
        uint256 protocolAmountCurrency;
        uint256 protocolAmountCoin;
        uint256 dopplerAmountCurrency;
        uint256 dopplerAmountCoin;
    }

    /// @notice Emitted when market rewards are distributed
    /// @param coin The address of the coin
    /// @param currency The address of the currency
    /// @param payoutRecipient The address of the creator rewards payout recipient
    /// @param platformReferrer The address of the platform referrer
    /// @param protocolRewardRecipient The address of the protocol reward recipient
    /// @param dopplerRecipient The address of the doppler recipient
    /// @param tradeReferrer The address of the trade referrer
    /// @param marketRewards The rewards accrued from the market's liquidity position
    event CoinMarketRewardsV4(
        address coin,
        address currency,
        address payoutRecipient,
        address platformReferrer,
        address tradeReferrer,
        address protocolRewardRecipient,
        address dopplerRecipient,
        MarketRewardsV4 marketRewards
    );
}

interface IMsgSender {
    function msgSender() external view returns (address);
}
