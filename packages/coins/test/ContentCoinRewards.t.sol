// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./utils/BaseTest.sol";
import {console} from "forge-std/console.sol";

import {CoinRewardsV4} from "../src/libs/CoinRewardsV4.sol";
import {IHasRewardsRecipients} from "../src/interfaces/IHasRewardsRecipients.sol";
import {UniV4SwapHelper} from "../src/libs/UniV4SwapHelper.sol";
import {FeeEstimatorHook} from "./utils/FeeEstimatorHook.sol";
import {RewardTestHelpers, RewardBalances} from "./utils/RewardTestHelpers.sol";
import {CoinConstants} from "../src/libs/CoinConstants.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ContentCoinRewardsTest is BaseTest {
    ContentCoin internal contentCoin;
    CreatorCoin internal backingCreatorCoin;

    address internal platformReferrer;
    address internal tradeReferrer;

    function setUp() public override {
        super.setUpWithBlockNumber(30267794);

        deal(address(zoraToken), address(poolManager), 1_000_000_000e18);

        backingCreatorCoin = CreatorCoin(_deployCreatorCoin());

        vm.label(address(backingCreatorCoin), "BACKING_CREATOR_COIN");

        // Set up referrer addresses for all tests
        platformReferrer = makeAddr("platformReferrer");
        tradeReferrer = makeAddr("tradeReferrer");
    }

    // Generic function to record token balances for all reward recipients
    function _recordBalances(IERC20 token) internal view returns (RewardBalances memory balances) {
        balances.creator = token.balanceOf(users.creator);
        balances.platformReferrer = token.balanceOf(platformReferrer);
        balances.tradeReferrer = token.balanceOf(tradeReferrer);
        balances.protocol = token.balanceOf(contentCoin.protocolRewardRecipient());
        balances.doppler = token.balanceOf(contentCoin.dopplerFeeRecipient());
    }

    // Helper function to record initial ZORA token balances for all reward recipients
    function _recordZoraBalances() internal view returns (RewardBalances memory balances) {
        return _recordBalances(zoraToken);
    }

    // Helper function to calculate ZORA token reward deltas after trade
    function _calculateZoraRewardDeltas(RewardBalances memory initialBalances) internal view returns (RewardBalances memory deltas) {
        deltas.creator = zoraToken.balanceOf(users.creator) - initialBalances.creator;
        deltas.platformReferrer = zoraToken.balanceOf(platformReferrer) - initialBalances.platformReferrer;
        deltas.tradeReferrer = zoraToken.balanceOf(tradeReferrer) - initialBalances.tradeReferrer;
        deltas.protocol = zoraToken.balanceOf(contentCoin.protocolRewardRecipient()) - initialBalances.protocol;
        deltas.doppler = zoraToken.balanceOf(contentCoin.dopplerFeeRecipient()) - initialBalances.doppler;
    }

    /// @dev Estimates the fees from a swap
    function _estimateLpFees(bytes memory commands, bytes[] memory inputs) internal returns (FeeEstimatorHook.FeeEstimatorState memory feeState) {
        uint256 snapshot = vm.snapshot();
        _deployFeeEstimatorHook(address(hook));

        // Execute the swap
        uint256 deadline = block.timestamp + 20;
        router.execute(commands, inputs, deadline);

        feeState = FeeEstimatorHook(payable(address(hook))).getFeeState();

        vm.revertToState(snapshot);
    }

    // Helper function to buy content coin
    function _buyContentCoin(address currencyIn, uint128 amountIn, bool hasTradeReferrer) internal returns (uint256 feeCurrency) {
        vm.warp(block.timestamp + 1 days);

        vm.startPrank(users.buyer);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), currencyIn, uint128(amountIn), uint48(block.timestamp + 1 days));

        // Build hook data with trade referrer if provided
        bytes memory hookData = hasTradeReferrer ? abi.encode(tradeReferrer) : bytes("");

        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            currencyIn,
            uint128(amountIn),
            address(contentCoin),
            0,
            contentCoin.getPoolKey(),
            hookData
        );

        // Estimate the total fees before executing
        FeeEstimatorHook.FeeEstimatorState memory feeState = _estimateLpFees(commands, inputs);
        feeCurrency = feeState.afterSwapCurrencyAmount;

        router.execute(commands, inputs, block.timestamp + 1 days);
        vm.stopPrank();
    }

    // Helper function to deploy content coin backed by creator coin
    function _deployContentCoin(bool hasPlatformReferrer) internal {
        // Then deploy content coin backed by the creator coin
        bytes memory poolConfig = _defaultPoolConfig(address(backingCreatorCoin));

        // Generate unique salt
        bytes32 uniqueSalt = keccak256(abi.encodePacked("content", address(backingCreatorCoin), block.timestamp, gasleft()));

        vm.prank(users.creator);
        (address contentCoinAddress, ) = factory.deploy(
            users.creator,
            _getDefaultOwners(),
            "https://content.com",
            "ContentCoin",
            "CONTENT",
            poolConfig,
            hasPlatformReferrer ? platformReferrer : address(0),
            address(0), // postDeployHook
            bytes(""), // postDeployHookData
            uniqueSalt
        );

        contentCoin = ContentCoin(contentCoinAddress);
        vm.label(address(contentCoin), "TEST_CONTENT_COIN");
    }

    // Helper function to deploy creator coin (backing for content coin)
    function _deployCreatorCoin() internal returns (address) {
        // Use the same multi-curve config as CreatorCoinRewards.t.sol
        int24[] memory tickLower = new int24[](1);
        int24[] memory tickUpper = new int24[](1);
        uint16[] memory numDiscoveryPositions = new uint16[](1);
        uint256[] memory maxDiscoverySupplyShare = new uint256[](1);

        tickLower[0] = -138_000;
        tickUpper[0] = 81_000;
        numDiscoveryPositions[0] = 11;
        maxDiscoverySupplyShare[0] = 0.25e18;

        bytes memory poolConfig = abi.encode(
            CoinConfigurationVersions.DOPPLER_MULTICURVE_UNI_V4_POOL_VERSION,
            address(zoraToken),
            tickLower,
            tickUpper,
            numDiscoveryPositions,
            maxDiscoverySupplyShare
        );

        // Generate unique salt
        bytes32 uniqueSalt = keccak256(abi.encodePacked("creator", block.timestamp, gasleft()));

        vm.prank(users.creator);
        address creatorCoinAddress = factory.deployCreatorCoin(
            users.creator,
            _getDefaultOwners(),
            "https://creator.com",
            "CreatorCoin",
            "CREATOR",
            poolConfig,
            address(0),
            uniqueSalt
        );

        return creatorCoinAddress;
    }

    /// @notice Test that fee estimation matches actual reward distribution
    function test_estimateAfterSwapCurrencyAmount() public {
        // Deploy content coin backed by creator coin
        _deployContentCoin(true);

        uint128 tradeAmount = 1000 ether;

        // First, get trader some backing creator coins
        address trader = users.buyer;
        deal(address(zoraToken), trader, tradeAmount * 2);
        _swapSomeCurrencyForCoin(ICoin(address(backingCreatorCoin)), address(zoraToken), tradeAmount, trader);

        // Record initial balances
        RewardBalances memory initialBalances = _recordZoraBalances();

        // Build swap command: Creator Coin -> Content Coin
        uint128 backingBalance = uint128(backingCreatorCoin.balanceOf(trader));

        vm.startPrank(trader);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), address(backingCreatorCoin), backingBalance, uint48(block.timestamp + 1 days));

        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            address(backingCreatorCoin),
            backingBalance,
            address(contentCoin),
            0,
            contentCoin.getPoolKey(),
            bytes("") // No trade referrer
        );

        // Estimate fees using the same pattern as CoinUniV4.t.sol
        FeeEstimatorHook.FeeEstimatorState memory feeState = _estimateLpFees(commands, inputs);

        // Execute actual swap
        router.execute(commands, inputs, block.timestamp + 20);
        vm.stopPrank();

        // Calculate actual total rewards distributed
        RewardBalances memory finalRewards = _calculateZoraRewardDeltas(initialBalances);
        uint256 totalActualRewards = RewardTestHelpers.getTotalRewards(finalRewards);

        // Verify that total actual rewards match the estimated afterSwapCurrencyAmount
        assertApproxEqRel(totalActualRewards, feeState.afterSwapCurrencyAmount, 0.25e18, "Total rewards should match estimated afterSwapCurrencyAmount");
    }

    /// @notice Test reward distribution with creator referrer only (no trade referrer, no platform referrer)
    function test_rewards_creator_referrer_only() public {
        // Deploy content coin backed by creator coin with creator referrer (inherits creator referrer)
        _deployContentCoin(true);

        uint128 tradeAmount = 1000 ether; // 1000 ZORA tokens

        // First, trader needs to get some backing creator coins to trade for content coin
        address trader = users.buyer;
        deal(address(zoraToken), trader, tradeAmount * 2); // Give extra for initial swap

        // Step 1: Swap ZORA for backing creator coin
        _swapSomeCurrencyForCoin(ICoin(address(backingCreatorCoin)), address(zoraToken), tradeAmount, trader);

        // Step 2: Record balances before content coin trade and perform the actual test trade
        RewardBalances memory initialBalances = _recordZoraBalances();

        // Swap backing creator coin for content coin
        uint128 backingBalance = uint128(backingCreatorCoin.balanceOf(trader));
        uint256 rewardsAmount = _buyContentCoin(address(backingCreatorCoin), backingBalance, false);

        RewardBalances memory rewards = _calculateZoraRewardDeltas(initialBalances);

        // Calculate expected rewards based on actual reward deltas (like creator coin tests do)
        uint256 totalRewards = rewardsAmount;
        RewardBalances memory expected = RewardTestHelpers.calculateExpectedRewards(totalRewards, true, false);
        RewardTestHelpers.assertRewardsApproxEqRelWithTolerance(rewards, expected, 0.25e18);
    }

    /// @notice Test reward distribution with trade referrer only (no creator referrer, no platform referrer)
    function test_rewards_trade_referrer_only() public {
        _deployContentCoin(false); // Deploy without platform referrer

        uint128 tradeAmount = 1000 ether;
        address trader = users.buyer;
        deal(address(zoraToken), trader, tradeAmount * 2);

        // Step 1: Get backing creator coins
        _swapSomeCurrencyForCoin(ICoin(address(backingCreatorCoin)), address(zoraToken), tradeAmount, trader);

        // Step 2: Test content coin trade
        RewardBalances memory initialBalances = _recordZoraBalances();
        uint128 backingBalance = uint128(backingCreatorCoin.balanceOf(trader));
        uint256 rewardsAmount = _buyContentCoin(address(backingCreatorCoin), backingBalance, true);
        RewardBalances memory rewards = _calculateZoraRewardDeltas(initialBalances);

        // Step 3: Validate rewards
        RewardBalances memory expected = RewardTestHelpers.calculateExpectedRewards(rewardsAmount, false, true);
        RewardTestHelpers.assertRewardsApproxEqRelWithTolerance(rewards, expected, 0.25e18);
    }

    /// @notice Test reward distribution with creator referrer + trade referrer (no platform referrer)
    function test_rewards_platform_and_trade_referrers() public {
        _deployContentCoin(true); // Deploy with platform referrer

        uint128 tradeAmount = 1000 ether;
        address trader = users.buyer;
        deal(address(zoraToken), trader, tradeAmount * 2);

        // Step 1: Get backing creator coins
        _swapSomeCurrencyForCoin(ICoin(address(backingCreatorCoin)), address(zoraToken), tradeAmount, trader);

        // Step 2: Test content coin trade
        RewardBalances memory initialBalances = _recordZoraBalances();
        uint128 backingBalance = uint128(backingCreatorCoin.balanceOf(trader));
        uint256 rewardsAmount = _buyContentCoin(address(backingCreatorCoin), backingBalance, true);
        RewardBalances memory rewards = _calculateZoraRewardDeltas(initialBalances);

        // Step 3: Validate rewards
        RewardBalances memory expected = RewardTestHelpers.calculateExpectedRewards(rewardsAmount, true, true);
        console.log("protocol rewards", rewards.protocol);
        console.log("expected protocol rewards", expected.protocol);
        RewardTestHelpers.assertRewardsApproxEqRelWithTolerance(rewards, expected, 0.25e18);
    }

    /// @notice Test reward distribution with no referrers (all address(0))
    function test_rewards_no_referrers() public {
        _deployContentCoin(false); // Deploy without platform referrer

        uint128 tradeAmount = 1000 ether;
        address trader = users.buyer;
        deal(address(zoraToken), trader, tradeAmount * 2);

        // Step 1: Get backing creator coins
        _swapSomeCurrencyForCoin(ICoin(address(backingCreatorCoin)), address(zoraToken), tradeAmount, trader);

        // Step 2: Test content coin trade
        RewardBalances memory initialBalances = _recordZoraBalances();
        uint128 backingBalance = uint128(backingCreatorCoin.balanceOf(trader));
        uint256 rewardsAmount = _buyContentCoin(address(backingCreatorCoin), backingBalance, false);
        RewardBalances memory rewards = _calculateZoraRewardDeltas(initialBalances);

        // Step 3: Validate rewards
        RewardBalances memory expected = RewardTestHelpers.calculateExpectedRewards(rewardsAmount, false, false);
        RewardTestHelpers.assertRewardsApproxEqRelWithTolerance(rewards, expected, 0.25e18);
    }

    function test_isNotLegacyCreatorCoinCategorization() public {
        vm.createSelectFork("base", 31835069);

        // Use the same content coin from the upgrades test
        address contentCoinAddress = 0x4E93A01c90f812284F71291a8d1415a904957156;

        // Test that the content coin is NOT categorized as a legacy creator coin
        bool isLegacy = CoinRewardsV4.isLegacyCreatorCoin(IHasRewardsRecipients(contentCoinAddress));

        assertFalse(isLegacy, "Content coin should NOT be categorized as legacy creator coin");
    }
}
