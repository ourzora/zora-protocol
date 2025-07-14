// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {ICoin} from "./ICoin.sol";
import {IUpgradeableV4Hook} from "./IUpgradeableV4Hook.sol";

interface IZoraV4CoinHook is IUpgradeableV4Hook {
    /// @notice Emitted when a swap is executed.
    /// @param sender The address of the sender.
    /// @param swapSender The address of the swap sender.
    /// @param isTrustedSwapSenderAddress Whether the swap sender is a trusted address. (Based on a registry of trusted addresses)
    /// @param key The pool key struct to identify the pool.
    /// @param poolKeyHash The hash of the pool key for indexing.
    /// @param params The swap parameters.
    /// @param amount0 The amount of token0.
    /// @param amount1 The amount of token1.
    /// @param isCoinBuy Whether the swap is a coin buy.
    /// @param hookData The data passed into the hook for the swap.
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
        bytes hookData,
        uint160 sqrtPriceX96
    );

    /// @notice Thrown when a non-coin is used to initialize a pool with this hook.
    /// @param coin The address of the coin.
    error NotACoin(address coin);

    /// @notice Coin version lookup cannot be the zero address.
    error CoinVersionLookupCannotBeZeroAddress();

    /// @notice Upgrade gate cannot be the zero address.
    error UpgradeGateCannotBeZeroAddress();

    /// @notice Thrown when a pool is not initialized for the hook.
    /// @param key The pool key struct to identify the pool.
    error NoCoinForHook(PoolKey key);

    /// @notice Thrown when a attempting to swap with a path that has no steps.
    error PathMustHaveAtLeastOneStep();

    /// @notice Thrown when a non-coin is used to access the functionality of a coin.
    error OnlyCoin(address caller, address expectedCoin);

    /// @notice The pool coin struct. Lists all the contract-created positions for the coin.
    struct PoolCoin {
        /// @notice The address of the coin.
        address coin;
        /// @notice The positions of the pool coin.
        LpPosition[] positions;
    }

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

    /// @notice Emitted when LP rewards are distributed
    /// @param coin The address of the coin
    /// @param currency The address of the currency
    /// @param amountCurrency The amount paid out
    /// @param tick The current tick
    /// @param liquidity The current liquidity
    event LpReward(address indexed coin, address indexed currency, uint256 amountCurrency, int24 tick, uint128 liquidity);

    /// @notice Returns the pool coin for a given pool key hash.
    /// @param poolKeyHash The hash of the pool key for indexing.
    /// @return poolCoin The pool coin confirmation data.
    function getPoolCoinByHash(bytes32 poolKeyHash) external view returns (IZoraV4CoinHook.PoolCoin memory);

    /// @notice Returns the pool coin for a given pool key.
    /// @param key The pool key.
    /// @return poolCoin The pool coin confirmation data.
    function getPoolCoin(PoolKey memory key) external view returns (IZoraV4CoinHook.PoolCoin memory);

    /// @notice Returns whether the sender is a trusted message sender.
    /// @param sender The address of the sender.
    /// @return isTrusted Whether the sender is a trusted message sender.
    function isTrustedMessageSender(address sender) external view returns (bool);
}
