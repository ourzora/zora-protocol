// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./utils/BaseTest.sol";
import {console} from "forge-std/console.sol";

import {ICreatorCoin} from "../src/interfaces/ICreatorCoin.sol";
import {ICreatorCoinHook} from "../src/interfaces/ICreatorCoinHook.sol";
import {IHasRewardsRecipients} from "../src/interfaces/IHasRewardsRecipients.sol";
import {CoinRewardsV4} from "../src/libs/CoinRewardsV4.sol";
import {UniV4SwapHelper} from "../src/libs/UniV4SwapHelper.sol";
import {FeeEstimatorHook} from "./utils/FeeEstimatorHook.sol";
import {RewardTestHelpers, RewardBalances} from "./utils/RewardTestHelpers.sol";
import {CoinConstants} from "../src/libs/CoinConstants.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CreatorCoinRewardsTest is BaseTest {
    CreatorCoin internal creatorCoin;

    address internal platformReferrer;
    address internal tradeReferrer;

    function setUp() public override {
        super.setUpWithBlockNumber(30267794);

        deal(address(zoraToken), address(poolManager), 1_000_000_000e18);

        // Set up referrer addresses for all tests
        platformReferrer = makeAddr("platformReferrer");
        tradeReferrer = makeAddr("tradeReferrer");
    }

    function _getMultiCurvePoolConfig() internal view returns (bytes memory) {
        int24[] memory tickLower = new int24[](1);
        int24[] memory tickUpper = new int24[](1);
        uint16[] memory numDiscoveryPositions = new uint16[](1);
        uint256[] memory maxDiscoverySupplyShare = new uint256[](1);

        tickLower[0] = -138_000;
        tickUpper[0] = 81_000;
        numDiscoveryPositions[0] = 11;
        maxDiscoverySupplyShare[0] = 0.25e18;

        return
            abi.encode(
                CoinConfigurationVersions.DOPPLER_MULTICURVE_UNI_V4_POOL_VERSION,
                address(zoraToken),
                tickLower,
                tickUpper,
                numDiscoveryPositions,
                maxDiscoverySupplyShare
            );
    }

    function _deployCreatorCoin(bool hasPlatformReferrer) internal {
        bytes memory poolConfig = _getMultiCurvePoolConfig();

        // Generate unique salt based on referrer addresses and block timestamp
        bytes32 uniqueSalt = keccak256(abi.encodePacked(platformReferrer, block.timestamp, gasleft()));

        vm.prank(users.creator);
        address creatorCoinAddress = factory.deployCreatorCoin(
            users.creator,
            _getDefaultOwners(),
            "https://test.com",
            "Testcoin",
            "TEST",
            poolConfig,
            hasPlatformReferrer ? platformReferrer : address(0),
            uniqueSalt // unique salt to prevent collisions
        );

        creatorCoin = CreatorCoin(creatorCoinAddress);
        vm.label(address(creatorCoin), "TEST_CREATOR_COIN");
    }

    /// @dev Estimates the fees from a swap, by deploying a test hook that doesn't distribute the fees
    /// and then reverting the state after the swap
    function _estimateLpFees(bytes memory commands, bytes[] memory inputs) internal returns (FeeEstimatorHook.FeeEstimatorState memory feeState) {
        uint256 snapshot = vm.snapshotState();
        _deployFeeEstimatorHook(address(hook));

        // Execute the swap
        uint256 deadline = block.timestamp + 20;
        router.execute(commands, inputs, deadline);

        feeState = FeeEstimatorHook(payable(address(hook))).getFeeState();

        vm.revertToState(snapshot);
    }

    // Generic function to record token balances for all reward recipients
    function _recordBalances(IERC20 token) internal view returns (RewardBalances memory balances) {
        balances.creator = token.balanceOf(users.creator);
        balances.platformReferrer = token.balanceOf(platformReferrer);
        balances.tradeReferrer = token.balanceOf(tradeReferrer);
        balances.protocol = token.balanceOf(creatorCoin.protocolRewardRecipient());
        balances.doppler = token.balanceOf(creatorCoin.dopplerFeeRecipient());
    }

    // Helper function to record initial ZORA token balances for all reward recipients
    function _recordZoraBalances() internal view returns (RewardBalances memory balances) {
        return _recordBalances(zoraToken);
    }

    // Helper function to record initial creator coin balances for all reward recipients
    function _recordCreatorCoinBalances() internal view returns (RewardBalances memory balances) {
        return _recordBalances(IERC20(address(creatorCoin)));
    }

    // Legacy function for backward compatibility
    function _recordInitialBalances() internal view returns (RewardBalances memory balances) {
        return _recordZoraBalances();
    }

    // Helper function to calculate ZORA token reward deltas after trade
    function _calculateZoraRewardDeltas(RewardBalances memory initialBalances) internal view returns (RewardBalances memory deltas) {
        return
            RewardTestHelpers.calculateTokenRewardDeltas(
                initialBalances,
                zoraToken,
                users.creator,
                platformReferrer,
                tradeReferrer,
                creatorCoin.protocolRewardRecipient(),
                creatorCoin.dopplerFeeRecipient()
            );
    }

    // Helper function to calculate creator coin reward deltas after trade
    function _calculateCreatorCoinRewardDeltas(RewardBalances memory initialBalances) internal view returns (RewardBalances memory deltas) {
        deltas.creator = creatorCoin.balanceOf(users.creator) - initialBalances.creator;
        // creatorReferrer is now unified with platformReferrer
        deltas.platformReferrer = creatorCoin.balanceOf(platformReferrer) - initialBalances.platformReferrer;
        deltas.tradeReferrer = creatorCoin.balanceOf(tradeReferrer) - initialBalances.tradeReferrer;
        deltas.protocol = creatorCoin.balanceOf(creatorCoin.protocolRewardRecipient()) - initialBalances.protocol;
        deltas.doppler = creatorCoin.balanceOf(creatorCoin.dopplerFeeRecipient()) - initialBalances.doppler;
    }

    // Legacy function for backward compatibility
    function _calculateRewardDeltas(RewardBalances memory initialBalances) internal view returns (RewardBalances memory deltas) {
        return _calculateZoraRewardDeltas(initialBalances);
    }

    // Helper function to perform trades with optional trade referrer and return fee estimation
    function _buyCreatorCoin(uint128 amountIn, bool hasTradeReferrer) internal returns (uint256 feeCurrency) {
        deal(address(zoraToken), users.buyer, amountIn);

        vm.warp(block.timestamp + 1 days);

        vm.startPrank(users.buyer);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), address(zoraToken), uint128(amountIn), uint48(block.timestamp + 1 days));

        // Build hook data with trade referrer if provided
        bytes memory hookData = hasTradeReferrer ? abi.encode(tradeReferrer) : bytes("");

        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            address(zoraToken),
            uint128(amountIn),
            address(creatorCoin),
            0,
            creatorCoin.getPoolKey(),
            hookData
        );

        // Estimate the total fees (3%) before executing
        FeeEstimatorHook.FeeEstimatorState memory feeState = _estimateLpFees(commands, inputs);

        feeCurrency = feeState.afterSwapCurrencyAmount;

        router.execute(commands, inputs, block.timestamp + 1 days);
        vm.stopPrank();
    }

    // Helper function to sell creator coin for ZORA tokens
    function _sellCreatorCoin(uint128 amountIn, bool hasTradeReferrer) internal returns (uint256 feeCurrency) {
        vm.startPrank(users.buyer);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), address(creatorCoin), uint128(amountIn), uint48(block.timestamp + 1 days));

        // Build hook data with trade referrer if provided
        bytes memory hookData = hasTradeReferrer ? abi.encode(tradeReferrer) : bytes("");

        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            address(creatorCoin),
            uint128(amountIn),
            address(zoraToken),
            0,
            creatorCoin.getPoolKey(),
            hookData
        );

        // Estimate the fees before executing
        FeeEstimatorHook.FeeEstimatorState memory feeState = _estimateLpFees(commands, inputs);

        feeCurrency = feeState.afterSwapCurrencyAmount;

        router.execute(commands, inputs, block.timestamp + 1 days);
        vm.stopPrank();
    }

    /// @notice Test exact reward distribution percentages with platform referrer only
    function test_rewards_platform_referrer_only() public {
        // Deploy CreatorCoin with platform referrer
        _deployCreatorCoin(true);

        uint128 tradeAmount = 1000 ether; // 1000 ZORA tokens

        // Record initial balances
        RewardBalances memory initialBalances = _recordInitialBalances();

        // Perform trade
        uint256 zoraFees = _buyCreatorCoin(tradeAmount, false);

        // Calculate reward deltas
        RewardBalances memory rewards = _calculateRewardDeltas(initialBalances);

        // Calculate market rewards from total fees
        // Use estimated market rewards (already accounts for LP deduction and slippage)
        RewardBalances memory expected = RewardTestHelpers.calculateExpectedRewards(zoraFees, true, false);
        RewardTestHelpers.assertRewardsApproxEqRel(rewards, expected);
    }

    /// @notice Test exact reward distribution percentages with trade referrer only
    function test_rewards_trade_referrer_only() public {
        // Deploy CreatorCoin with no platform referrer
        _deployCreatorCoin(false);

        uint128 tradeAmount = 1000 ether; // 1000 ZORA tokens

        // Record initial balances
        RewardBalances memory initialBalances = _recordInitialBalances();

        // Perform trade with trade referrer
        uint256 zoraFees = _buyCreatorCoin(tradeAmount, true);

        // Calculate reward deltas
        RewardBalances memory rewards = _calculateRewardDeltas(initialBalances);

        // Calculate market rewards from total fees
        // Use estimated market rewards (already accounts for LP deduction and slippage)
        RewardBalances memory expected = RewardTestHelpers.calculateExpectedRewards(zoraFees, false, true);
        RewardTestHelpers.assertRewardsApproxEqRel(rewards, expected);
    }

    /// @notice Test exact reward distribution percentages with both platform and trade referrers
    function test_rewards_both_referrers() public {
        // Deploy CreatorCoin with platform referrer
        _deployCreatorCoin(true);

        uint128 tradeAmount = 1000 ether; // 1000 ZORA tokens

        // Record initial balances
        RewardBalances memory initialBalances = _recordInitialBalances();

        // Perform trade with both referrers
        uint256 zoraFees = _buyCreatorCoin(tradeAmount, true);

        // Calculate reward deltas
        RewardBalances memory rewards = _calculateRewardDeltas(initialBalances);

        // Calculate market rewards from total fees
        // Use estimated market rewards (already accounts for LP deduction and slippage)
        RewardBalances memory expected = RewardTestHelpers.calculateExpectedRewards(zoraFees, true, true);
        RewardTestHelpers.assertRewardsApproxEqRel(rewards, expected);
    }

    /// @notice Test exact reward distribution percentages with no referrers (baseline case)
    function test_rewards_no_referrers() public {
        // Deploy CreatorCoin with no platform referrer
        _deployCreatorCoin(false);

        uint128 tradeAmount = 1000 ether; // 1000 ZORA tokens

        // Record initial balances
        RewardBalances memory initialBalances = _recordInitialBalances();

        // Perform trade with no trade referrer
        uint256 zoraFees = _buyCreatorCoin(tradeAmount, false);

        // Calculate reward deltas
        RewardBalances memory rewards = _calculateRewardDeltas(initialBalances);

        // Calculate market rewards from total fees
        // Use estimated market rewards (already accounts for LP deduction and slippage)
        RewardBalances memory expected = RewardTestHelpers.calculateExpectedRewards(zoraFees, false, false);
        RewardTestHelpers.assertRewardsApproxEqRel(rewards, expected);
    }

    /// @notice Test buy-then-sell creator coin with both referrers set
    function test_buy_then_sell_both_referrers() public {
        uint128 buyAmount = 100 ether; // Fixed amount

        // Deploy CreatorCoin with platform referrer
        _deployCreatorCoin(true);

        // Step 1: Buy creator coin (ZORA -> Creator Coin)
        _buyCreatorCoin(buyAmount, true);

        // Get buyer's creator coin balance after purchase
        uint256 creatorCoinBalance = creatorCoin.balanceOf(users.buyer);
        require(creatorCoinBalance > 0, "Buyer must have creator coin balance to sell");

        // Record initial balances for both ZORA and creator coin
        RewardBalances memory initialZoraBalances = _recordZoraBalances();

        // Step 2: Sell creator coin (Creator Coin -> ZORA)
        uint128 sellAmount = uint128(creatorCoinBalance);
        uint256 sellZoraFees = _sellCreatorCoin(sellAmount, true);

        // Calculate final reward deltas for both currencies
        RewardBalances memory finalZoraRewards = _calculateZoraRewardDeltas(initialZoraBalances);

        // Calculate total market rewards from both trades
        RewardBalances memory expectedTotalRewards = RewardTestHelpers.calculateExpectedRewards(sellZoraFees, true, true);

        // Validate ZORA token distributions (where all final rewards end up)
        RewardTestHelpers.assertRewardsApproxEqRel(finalZoraRewards, expectedTotalRewards);
    }

    /// @notice Test that fee estimation matches actual total reward distribution
    function test_estimateAfterSwapCurrencyAmount() public {
        // Deploy CreatorCoin with platform referrer
        _deployCreatorCoin(true);

        uint128 tradeAmount = 1 ether; // Much smaller amount for testing

        // Build swap command but don't execute yet
        deal(address(zoraToken), users.buyer, tradeAmount);
        vm.startPrank(users.buyer);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), address(zoraToken), tradeAmount, uint48(block.timestamp + 1 days));

        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            address(zoraToken),
            tradeAmount,
            address(creatorCoin),
            0,
            creatorCoin.getPoolKey(),
            bytes("") // No trade referrer
        );

        // Estimate fees using FeeEstimatorHook
        FeeEstimatorHook.FeeEstimatorState memory feeState = _estimateLpFees(commands, inputs);

        // Record initial balances
        RewardBalances memory initialBalances = _recordInitialBalances();

        // Execute actual swap
        router.execute(commands, inputs, block.timestamp + 20);
        vm.stopPrank();

        // Calculate total actual rewards distributed
        RewardBalances memory finalRewards = _calculateZoraRewardDeltas(initialBalances);
        uint256 totalActualRewards = finalRewards.creator +
            finalRewards.platformReferrer +
            finalRewards.tradeReferrer +
            finalRewards.protocol +
            finalRewards.doppler;

        // Verify that total actual rewards match the estimated afterSwapCurrencyAmount
        assertApproxEqRel(totalActualRewards, feeState.afterSwapCurrencyAmount, 0.25e18, "Total rewards should match estimated afterSwapCurrencyAmount");
    }

    function test_isLegacyCreatorCoinCategorization() public {
        vm.createSelectFork("base", 31872861);

        // Use the same creator coin from the upgrades test
        address creatorCoinAddress = 0x2F03aB8fD97F5874bc3274C296Bb954Ae92EdA34;

        // Test that the legacy creator coin is correctly categorized as a creator coin
        bool isLegacy = CoinRewardsV4.isLegacyCreatorCoin(IHasRewardsRecipients(creatorCoinAddress));

        assertTrue(isLegacy, "Legacy creator coin should be categorized as legacy creator coin");
    }
}
