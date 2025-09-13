// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BaseCoin} from "./BaseCoin.sol";
import {CoinConstants} from "./libs/CoinConstants.sol";
import {MarketConstants} from "./libs/MarketConstants.sol";
import {IHasCoinType} from "./interfaces/ICoin.sol";

/**
 * @title ContentCoin
 * @notice Content coin implementation that uses creator coins as backing currency
 * @dev Inherits from BaseCoin and implements content-specific distribution logic
 */
contract ContentCoin is BaseCoin {
    /// @notice The constructor for the static ContentCoin contract deployment shared across all content coins.
    /// @dev All arguments are required and cannot be set to the 0 address.
    /// @param protocolRewardRecipient_ The address of the protocol reward recipient
    /// @param protocolRewards_ The address of the protocol rewards contract
    /// @param poolManager_ The address of the pool manager
    /// @param airlock_ The address of the Airlock contract, ownership is used for a protocol fee split.
    constructor(
        address protocolRewardRecipient_,
        address protocolRewards_,
        IPoolManager poolManager_,
        address airlock_
    ) BaseCoin(protocolRewardRecipient_, protocolRewards_, poolManager_, airlock_) {}

    /// @dev The initial mint and distribution of the coin supply.
    ///      Implements content coin specific distribution: 990M to liquidity pool, 10M to creator.
    function _handleInitialDistribution() internal virtual override {
        // Mint the total supply to the coin contract
        _mint(address(this), CoinConstants.MAX_TOTAL_SUPPLY);

        // Distribute the creator launch reward to the payout recipient
        _transfer(address(this), payoutRecipient, CoinConstants.CREATOR_LAUNCH_REWARD);

        // Transfer the market supply to the hook for liquidity
        _transfer(address(this), address(poolKey.hooks), balanceOf(address(this)));
    }

    function totalSupplyForPositions() external pure override returns (uint256) {
        return MarketConstants.CONTENT_COIN_MARKET_SUPPLY;
    }

    function coinType() external pure override returns (IHasCoinType.CoinType) {
        return IHasCoinType.CoinType.Content;
    }
}
