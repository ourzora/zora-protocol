// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.28;

import {CoinConstants} from "./libs/CoinConstants.sol";
import {TickerUtils} from "./libs/TickerUtils.sol";
import {IHooks, PoolConfiguration, PoolKey, ICoin} from "./interfaces/ICoin.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BaseCoin} from "./BaseCoin.sol";
import {IHasCoinType} from "./interfaces/ICoin.sol";
import {ITrendCoin} from "./interfaces/ITrendCoin.sol";

/// @title TrendCoin
/// @notice Trend coin implementation with no creator payout recipient
/// @dev TrendCoins have 100% of supply in the liquidity pool with no creator allocation.
///      Unlike ContentCoin and CreatorCoin, TrendCoins do not have a payoutRecipient or platformReferrer.
contract TrendCoin is BaseCoin, ITrendCoin {
    /// @notice Base URI for trend coin metadata
    string internal constant TREND_COIN_BASE_URI = "https://trends.theme.wtf/trend/";

    address internal immutable metadataManager;

    constructor(
        address protocolRewardRecipient_,
        address protocolRewards_,
        IPoolManager poolManager_,
        address airlock_,
        address metadataManager_
    ) BaseCoin(protocolRewardRecipient_, protocolRewards_, poolManager_, airlock_) initializer {
        // Zero address is valid when metadata is intended to be non-updatable
        metadataManager = metadataManager_;
    }

    function totalSupplyForPositions() external pure override returns (uint256) {
        return CoinConstants.TOTAL_SUPPLY;
    }

    function coinType() external pure override returns (IHasCoinType.CoinType) {
        return IHasCoinType.CoinType.Trend;
    }

    function setContractURI(string memory newURI) external override {
        require(msg.sender == metadataManager, OnlyMetadataManager());
        _setContractURI(newURI);
    }

    function setNameAndSymbol(string memory newName, string memory newSymbol) external override {
        require(msg.sender == metadataManager, OnlyMetadataManager());
        _setNameAndSymbol(newName, newSymbol);
    }

    /// @inheritdoc ITrendCoin
    function initializeTrendCoin(
        address[] memory owners_,
        string memory symbol_,
        PoolKey memory poolKey_,
        uint160 sqrtPriceX96,
        PoolConfiguration memory poolConfiguration_
    ) external {
        // Validate ticker characters
        TickerUtils.requireValidateTickerCharacters(symbol_);

        // Generate URI from base URI + encoded symbol
        string memory uri = string.concat(TREND_COIN_BASE_URI, symbol_);

        // Call parent initialize with derived values
        // name = symbol for trend coins
        // The initializer modifier is on BaseCoin.initialize, not here
        BaseCoin.initialize({
            payoutRecipient_: address(0),
            owners_: owners_,
            tokenURI_: uri,
            name_: symbol_,
            symbol_: symbol_,
            platformReferrer_: address(0),
            currency_: CoinConstants.CREATOR_COIN_CURRENCY,
            poolKey_: poolKey_,
            sqrtPriceX96: sqrtPriceX96,
            poolConfiguration_: poolConfiguration_
        });
    }

    /// @dev Legacy initialize function for ICoin compatibility
    /// @notice Prefer using initializeTrendCoin for new deployments
    function initialize(
        address /* payoutRecipient_ */,
        address[] memory /* owners_ */,
        string memory /* tokenURI_ */,
        string memory /* name_ */,
        string memory /* symbol_ */,
        address /* platformReferrer_ */,
        address /* currency_ */,
        PoolKey memory /* poolKey_ */,
        uint160 /* sqrtPriceX96 */,
        PoolConfiguration memory /* poolConfiguration_ */
    ) public pure override {
        revert UseSpecificTrendCoinInitialize();
    }

    /// @dev The initial mint and distribution of the coin supply.
    ///      TrendCoins have 100% of supply in the liquidity pool.
    function _handleInitialDistribution() internal override {
        _mint(address(this), CoinConstants.TOTAL_SUPPLY);
        _transfer(address(this), address(poolKey.hooks), CoinConstants.TOTAL_SUPPLY);
    }

    /// @notice TrendCoins have no platform referrer - always returns address(0)
    /// @dev Overrides BaseCoin's platformReferrer which defaults to protocolRewardRecipient when not set
    function platformReferrer() external pure override returns (address) {
        return address(0);
    }
}
