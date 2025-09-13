// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.28;

import {ICreatorCoin} from "./interfaces/ICreatorCoin.sol";
import {CreatorCoinConstants} from "./libs/CreatorCoinConstants.sol";
import {IHooks, PoolConfiguration, PoolKey, ICoin} from "./interfaces/ICoin.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BaseCoin} from "./BaseCoin.sol";
import {IHasCoinType} from "./interfaces/ICoin.sol";
import {MarketConstants} from "./libs/MarketConstants.sol";

contract CreatorCoin is ICreatorCoin, BaseCoin {
    uint256 public vestingStartTime;
    uint256 public vestingEndTime;
    uint256 public totalClaimed;

    constructor(
        address protocolRewardRecipient_,
        address protocolRewards_,
        IPoolManager poolManager_,
        address airlock_
    ) BaseCoin(protocolRewardRecipient_, protocolRewards_, poolManager_, airlock_) initializer {}

    function totalSupplyForPositions() external pure override returns (uint256) {
        return MarketConstants.CREATOR_COIN_MARKET_SUPPLY;
    }

    function coinType() external pure override returns (IHasCoinType.CoinType) {
        return IHasCoinType.CoinType.Creator;
    }

    function initialize(
        address payoutRecipient_,
        address[] memory owners_,
        string memory tokenURI_,
        string memory name_,
        string memory symbol_,
        address platformReferrer_,
        address currency_,
        PoolKey memory poolKey_,
        uint160 sqrtPriceX96,
        PoolConfiguration memory poolConfiguration_
    ) public override(BaseCoin, ICoin) {
        require(currency_ == CreatorCoinConstants.CURRENCY, InvalidCurrency());

        super.initialize({
            payoutRecipient_: payoutRecipient_,
            owners_: owners_,
            tokenURI_: tokenURI_,
            name_: name_,
            symbol_: symbol_,
            platformReferrer_: platformReferrer_,
            currency_: currency_,
            poolKey_: poolKey_,
            sqrtPriceX96: sqrtPriceX96,
            poolConfiguration_: poolConfiguration_
        });

        vestingStartTime = block.timestamp;
        vestingEndTime = block.timestamp + CreatorCoinConstants.CREATOR_VESTING_DURATION;
    }

    /// @dev The initial mint and distribution of the coin supply.
    ///      Implements creator coin specific distribution: 500M to liquidity pool, 500M vested to creator.
    function _handleInitialDistribution() internal override {
        _mint(address(this), CreatorCoinConstants.TOTAL_SUPPLY);

        _transfer(address(this), address(poolKey.hooks), MarketConstants.CREATOR_COIN_MARKET_SUPPLY);
    }

    /// @notice Allows the creator payout recipient to claim vested tokens
    /// @dev Optimized for frequent calls from Uniswap V4 hooks
    /// @return claimAmount The amount of tokens claimed
    function claimVesting() external returns (uint256) {
        uint256 claimAmount = getClaimableAmount();

        // Early return if nothing to claim (gas efficient for frequent calls)
        if (claimAmount == 0) {
            return 0;
        }

        // Update total claimed before transfer
        totalClaimed += claimAmount;

        // Transfer directly to the payout recipient
        _transfer(address(this), payoutRecipient, claimAmount);

        emit CreatorVestingClaimed(payoutRecipient, claimAmount, totalClaimed, vestingStartTime, vestingEndTime);

        return claimAmount;
    }

    /// @notice Get currently claimable amount without claiming
    /// @return The amount that can be claimed right now
    function getClaimableAmount() public view returns (uint256) {
        uint256 vestedAmount = _calculateVestedAmount(block.timestamp);
        return vestedAmount > totalClaimed ? vestedAmount - totalClaimed : 0;
    }

    /// @notice Calculate total vested amount at given timestamp
    /// @param timestamp The timestamp to calculate vesting for
    /// @return The total amount vested at the given timestamp
    function _calculateVestedAmount(uint256 timestamp) internal view returns (uint256) {
        // Before vesting starts
        if (timestamp <= vestingStartTime) {
            return 0;
        }

        // After vesting ends - fully vested
        if (timestamp >= vestingEndTime) {
            return CreatorCoinConstants.CREATOR_VESTING_SUPPLY;
        }

        // Linear vesting: (elapsed_time / total_duration) * total_amount
        uint256 elapsedTime = timestamp - vestingStartTime;

        // Multiply first to avoid precision loss
        return (CreatorCoinConstants.CREATOR_VESTING_SUPPLY * elapsedTime) / CreatorCoinConstants.CREATOR_VESTING_DURATION;
    }
}
