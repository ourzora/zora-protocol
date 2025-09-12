// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {CoinRewardsV4} from "../../src/libs/CoinRewardsV4.sol";
import {FeeEstimatorHook} from "./FeeEstimatorHook.sol";
import {CoinConstants} from "../../src/libs/CoinConstants.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";

// Shared struct to track balance changes for reward recipients
struct RewardBalances {
    uint256 creator;
    uint256 platformReferrer;
    uint256 tradeReferrer;
    uint256 protocol;
    uint256 doppler;
}

library RewardTestHelpers {
    Vm private constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    // Helper function to calculate reward based on BPS
    function calculateReward(uint256 total, uint256 bps) internal pure returns (uint256) {
        return (total * bps) / 10_000;
    }

    function calculateExpectedRewards(
        uint256 marketRewards,
        bool hasPlatformReferrer,
        bool hasTradeReferrer
    ) internal pure returns (RewardBalances memory rewards) {
        rewards.creator = calculateReward(marketRewards, CoinRewardsV4.CREATOR_REWARD_BPS);
        rewards.platformReferrer = hasPlatformReferrer ? calculateReward(marketRewards, CoinRewardsV4.CREATE_REFERRAL_REWARD_BPS) : 0;
        rewards.tradeReferrer = hasTradeReferrer ? calculateReward(marketRewards, CoinRewardsV4.TRADE_REFERRAL_REWARD_BPS) : 0;
        rewards.doppler = calculateReward(marketRewards, CoinRewardsV4.DOPPLER_REWARD_BPS);
        rewards.protocol = marketRewards - rewards.creator - rewards.platformReferrer - rewards.tradeReferrer - rewards.doppler;
    }

    // Helper function to assert reward distributions match expected RewardBalances
    function assertRewardsApproxEqRel(RewardBalances memory actual, RewardBalances memory expected) internal pure {
        vm.assertApproxEqRel(actual.creator, expected.creator, 0.25e18, "Creator reward amount");
        vm.assertApproxEqRel(actual.platformReferrer, expected.platformReferrer, 0.25e18, "Platform referrer reward amount");
        vm.assertApproxEqRel(actual.tradeReferrer, expected.tradeReferrer, 0.25e18, "Trade referrer reward amount");
        vm.assertApproxEqRel(actual.doppler, expected.doppler, 0.25e18, "Doppler reward amount");
        vm.assertApproxEqRel(actual.protocol, expected.protocol, 0.25e18, "Protocol reward amount");
    }

    // Helper function to assert with higher tolerance for complex conversions
    function assertRewardsApproxEqRelWithTolerance(RewardBalances memory actual, RewardBalances memory expected, uint256 tolerance) internal pure {
        vm.assertApproxEqRel(actual.creator, expected.creator, tolerance, "Creator reward amount");
        vm.assertApproxEqRel(actual.platformReferrer, expected.platformReferrer, tolerance, "Platform referrer reward amount");
        vm.assertApproxEqRel(actual.tradeReferrer, expected.tradeReferrer, tolerance, "Trade referrer reward amount");
        vm.assertApproxEqRel(actual.doppler, expected.doppler, tolerance, "Doppler reward amount");
        vm.assertApproxEqRel(actual.protocol, expected.protocol, tolerance, "Protocol reward amount");
    }

    // Generic function to record token balances for all reward recipients
    function recordBalances(
        IERC20 token,
        address creator,
        address platformReferrer,
        address tradeReferrer,
        address protocolRecipient,
        address dopplerRecipient
    ) internal view returns (RewardBalances memory balances) {
        balances.creator = token.balanceOf(creator);
        balances.platformReferrer = token.balanceOf(platformReferrer);
        balances.tradeReferrer = token.balanceOf(tradeReferrer);
        balances.protocol = token.balanceOf(protocolRecipient);
        balances.doppler = token.balanceOf(dopplerRecipient);
    }

    // Helper function to calculate reward deltas between two balance snapshots
    function calculateRewardDeltas(
        RewardBalances memory initialBalances,
        RewardBalances memory finalBalances
    ) internal pure returns (RewardBalances memory deltas) {
        deltas.creator = finalBalances.creator - initialBalances.creator;
        deltas.platformReferrer = finalBalances.platformReferrer - initialBalances.platformReferrer;
        deltas.tradeReferrer = finalBalances.tradeReferrer - initialBalances.tradeReferrer;
        deltas.protocol = finalBalances.protocol - initialBalances.protocol;
        deltas.doppler = finalBalances.doppler - initialBalances.doppler;
    }

    // Helper function to sum total rewards
    function getTotalRewards(RewardBalances memory rewards) internal pure returns (uint256) {
        return rewards.creator + rewards.platformReferrer + rewards.tradeReferrer + rewards.protocol + rewards.doppler;
    }

    // Helper function to calculate reward deltas after trade for any token
    function calculateTokenRewardDeltas(
        RewardBalances memory initialBalances,
        IERC20 token,
        address creator,
        address platformReferrer,
        address tradeReferrer,
        address protocolRecipient,
        address dopplerRecipient
    ) internal view returns (RewardBalances memory deltas) {
        deltas.creator = token.balanceOf(creator) - initialBalances.creator;
        deltas.platformReferrer = token.balanceOf(platformReferrer) - initialBalances.platformReferrer;
        deltas.tradeReferrer = token.balanceOf(tradeReferrer) - initialBalances.tradeReferrer;
        deltas.protocol = token.balanceOf(protocolRecipient) - initialBalances.protocol;
        deltas.doppler = token.balanceOf(dopplerRecipient) - initialBalances.doppler;
    }
}
