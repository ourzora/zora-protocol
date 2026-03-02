// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseTest} from "./utils/BaseTest.sol";
import {console} from "forge-std/console.sol";

import {IZoraFactory} from "../src/interfaces/IZoraFactory.sol";
import {IHasRewardsRecipients} from "../src/interfaces/IHasRewardsRecipients.sol";
import {IHasCoinType} from "../src/interfaces/ICoin.sol";
import {CoinRewardsV4} from "../src/libs/CoinRewardsV4.sol";
import {UniV4SwapHelper} from "../src/libs/UniV4SwapHelper.sol";
import {FeeEstimatorHook} from "./utils/FeeEstimatorHook.sol";
import {RewardTestHelpers, RewardBalances} from "./utils/RewardTestHelpers.sol";
import {CoinConstants} from "../src/libs/CoinConstants.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TrendCoin} from "../src/TrendCoin.sol";
import {ITrendCoin} from "../src/interfaces/ITrendCoin.sol";
import {ITrendCoinErrors} from "../src/interfaces/ITrendCoinErrors.sol";
import {ICoin} from "../src/interfaces/ICoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {CoinConfigurationVersions} from "../src/libs/CoinConfigurationVersions.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ZoraFactoryImpl} from "../src/ZoraFactoryImpl.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ProxyShim} from "../src/utils/ProxyShim.sol";
import {ZoraFactory} from "../src/proxy/ZoraFactory.sol";
import {ZoraHookRegistry} from "../src/hook-registry/ZoraHookRegistry.sol";
import {PoolConfiguration} from "../src/types/PoolConfiguration.sol";

contract TrendCoinTest is BaseTest {
    TrendCoin internal trendCoin;

    function setUp() public override {
        super.setUpNonForked();
    }

    // ============ Factory Deployment Tests ============

    function test_deployTrendCoin_basic() public {
        string memory symbol = "TESTTREND";

        (address coinAddress, ) = factory.deployTrendCoin(symbol, address(0), "");

        trendCoin = TrendCoin(coinAddress);

        // Verify basic properties
        assertEq(trendCoin.symbol(), symbol, "Symbol should match");
        assertEq(trendCoin.name(), symbol, "Name should equal symbol for trend coins");
        assertEq(uint8(trendCoin.coinType()), uint8(IHasCoinType.CoinType.Trend), "Should be Trend coin type");

        // TrendCoins have no payout recipient or platform referrer
        assertEq(trendCoin.payoutRecipient(), address(0), "Payout recipient should be zero");
        assertEq(trendCoin.platformReferrer(), address(0), "Platform referrer should be zero");
    }

    function test_deployTrendCoin_emitsEventWithPoolConfig() public {
        string memory symbol = "EVENTTEST";

        // Get expected pool config
        bytes memory expectedPoolConfig = CoinConfigurationVersions.defaultConfig(CoinConstants.CREATOR_COIN_CURRENCY);

        vm.expectEmit(true, false, false, false);
        emit IZoraFactory.TrendCoinCreated(
            address(this),
            symbol,
            address(0),
            PoolKey(Currency.wrap(address(0)), Currency.wrap(address(0)), 0, 0, hook),
            bytes32(0),
            expectedPoolConfig,
            ""
        );

        (address coinAddress, ) = factory.deployTrendCoin(symbol, address(0), "");

        // Verify coin was created
        assertTrue(coinAddress != address(0), "Coin should be created");
    }

    function test_deployTrendCoin_addressCanBePredicted() public {
        string memory symbol = "PREDICT";

        // Get predicted address before deployment
        address predictedAddress = factory.trendCoinAddress(symbol);

        // Deploy the coin
        (address actualAddress, ) = factory.deployTrendCoin(symbol, address(0), "");

        // Verify prediction matches
        assertEq(actualAddress, predictedAddress, "Predicted address should match actual");
    }

    function test_deployTrendCoin_tickerUniqueness() public {
        string memory symbol = "UNIQUE";

        // Deploy first coin
        factory.deployTrendCoin(symbol, address(0), "");

        // Try to deploy with same ticker - should revert
        vm.expectRevert(abi.encodeWithSelector(ITrendCoinErrors.TickerAlreadyUsed.selector, symbol));
        factory.deployTrendCoin(symbol, address(0), "");
    }

    function test_deployTrendCoin_tickerCaseInsensitive() public {
        // Deploy with lowercase
        factory.deployTrendCoin("test", address(0), "");

        // Try to deploy with uppercase - should revert (same ticker, different case)
        vm.expectRevert(abi.encodeWithSelector(ITrendCoinErrors.TickerAlreadyUsed.selector, "TEST"));
        factory.deployTrendCoin("TEST", address(0), "");

        // Try with mixed case - should also revert
        vm.expectRevert(abi.encodeWithSelector(ITrendCoinErrors.TickerAlreadyUsed.selector, "TeSt"));
        factory.deployTrendCoin("TeSt", address(0), "");
    }

    function test_deployTrendCoin_differentTickersAllowed() public {
        // Deploy multiple coins with different tickers
        (address coin1, ) = factory.deployTrendCoin("TICKER1", address(0), "");
        (address coin2, ) = factory.deployTrendCoin("TICKER2", address(0), "");
        (address coin3, ) = factory.deployTrendCoin("TICKER3", address(0), "");

        // All should be different addresses
        assertTrue(coin1 != coin2, "Coin1 and Coin2 should have different addresses");
        assertTrue(coin2 != coin3, "Coin2 and Coin3 should have different addresses");
        assertTrue(coin1 != coin3, "Coin1 and Coin3 should have different addresses");
    }

    function test_deployTrendCoin_fullSupplyToPool() public {
        string memory symbol = "FULLPOOL";

        (address coinAddress, ) = factory.deployTrendCoin(symbol, address(0), "");
        trendCoin = TrendCoin(coinAddress);

        // Total supply should be the full 1B
        assertEq(trendCoin.totalSupply(), CoinConstants.TOTAL_SUPPLY, "Total supply should be 1B");

        // Verify token allocation - the coin itself should have 0 balance (all sent to hook for pool)
        assertEq(trendCoin.balanceOf(coinAddress), 0, "Coin should have no balance");
    }

    // ============ Symbol Validation Tests ============

    function test_deployTrendCoin_validSymbols_lettersOnly() public {
        // Test uppercase letters
        (address coin1, ) = factory.deployTrendCoin("ABC", address(0), "");
        assertTrue(coin1 != address(0), "Coin with uppercase letters should deploy");

        // Test lowercase letters
        (address coin2, ) = factory.deployTrendCoin("xyz", address(0), "");
        assertTrue(coin2 != address(0), "Coin with lowercase letters should deploy");

        // Test mixed case
        (address coin3, ) = factory.deployTrendCoin("TestCoin", address(0), "");
        assertTrue(coin3 != address(0), "Coin with mixed case letters should deploy");
    }

    function test_deployTrendCoin_validSymbols_numbersOnly() public {
        (address coin1, ) = factory.deployTrendCoin("123", address(0), "");
        assertTrue(coin1 != address(0), "Coin with numbers should deploy");

        (address coin2, ) = factory.deployTrendCoin("456", address(0), "");
        assertTrue(coin2 != address(0), "Coin with different numbers should deploy");
    }

    function test_deployTrendCoin_validSymbols_dashOnly() public {
        (address coin1, ) = factory.deployTrendCoin("-", address(0), "");
        assertTrue(coin1 != address(0), "Coin with single dash should deploy");

        (address coin2, ) = factory.deployTrendCoin("--", address(0), "");
        assertTrue(coin2 != address(0), "Coin with double dash should deploy");

        (address coin3, ) = factory.deployTrendCoin("---", address(0), "");
        assertTrue(coin3 != address(0), "Coin with triple dash should deploy");
    }

    function test_deployTrendCoin_validSymbols_spaceOnly() public {
        (address coin1, ) = factory.deployTrendCoin(" ", address(0), "");
        assertTrue(coin1 != address(0), "Coin with single space should deploy");

        (address coin2, ) = factory.deployTrendCoin("  ", address(0), "");
        assertTrue(coin2 != address(0), "Coin with double space should deploy");

        (address coin3, ) = factory.deployTrendCoin("   ", address(0), "");
        assertTrue(coin3 != address(0), "Coin with triple space should deploy");
    }

    function test_deployTrendCoin_validSymbols_allAllowedCharacters() public {
        (address coin1, ) = factory.deployTrendCoin("ABC-123 xyz", address(0), "");
        assertTrue(coin1 != address(0), "Coin with all character types should deploy");

        (address coin2, ) = factory.deployTrendCoin("Test-123 Coin", address(0), "");
        assertTrue(coin2 != address(0), "Coin with mixed valid characters should deploy");
    }

    struct InvalidSymbolTestCase {
        string symbol;
    }

    function fixtureInvalidSymbols() public pure returns (InvalidSymbolTestCase[] memory) {
        InvalidSymbolTestCase[] memory cases = new InvalidSymbolTestCase[](34);
        cases[0] = InvalidSymbolTestCase("TEST!");
        cases[1] = InvalidSymbolTestCase("TEST@");
        cases[2] = InvalidSymbolTestCase("TEST#");
        cases[3] = InvalidSymbolTestCase("TEST$");
        cases[4] = InvalidSymbolTestCase("TEST%");
        cases[5] = InvalidSymbolTestCase("TEST^");
        cases[6] = InvalidSymbolTestCase("TEST&");
        cases[7] = InvalidSymbolTestCase("TEST*");
        cases[8] = InvalidSymbolTestCase("TEST(");
        cases[9] = InvalidSymbolTestCase("TEST)");
        cases[10] = InvalidSymbolTestCase("TEST_");
        cases[11] = InvalidSymbolTestCase("TEST+");
        cases[12] = InvalidSymbolTestCase("TEST=");
        cases[13] = InvalidSymbolTestCase("TEST[");
        cases[14] = InvalidSymbolTestCase("TEST]");
        cases[15] = InvalidSymbolTestCase("TEST{");
        cases[16] = InvalidSymbolTestCase("TEST}");
        cases[17] = InvalidSymbolTestCase("TEST|");
        cases[18] = InvalidSymbolTestCase("TEST\\");
        cases[19] = InvalidSymbolTestCase("TEST:");
        cases[20] = InvalidSymbolTestCase("TEST;");
        cases[21] = InvalidSymbolTestCase('TEST"');
        cases[22] = InvalidSymbolTestCase("TEST'");
        cases[23] = InvalidSymbolTestCase("TEST<");
        cases[24] = InvalidSymbolTestCase("TEST>");
        cases[25] = InvalidSymbolTestCase("TEST,");
        cases[26] = InvalidSymbolTestCase("TEST.");
        cases[27] = InvalidSymbolTestCase("TEST?");
        cases[28] = InvalidSymbolTestCase("TEST/");
        cases[29] = InvalidSymbolTestCase("TEST~");
        cases[30] = InvalidSymbolTestCase("TEST_COIN");
        cases[31] = InvalidSymbolTestCase("TEST.COIN");
        cases[32] = InvalidSymbolTestCase("TEST!@#");
        cases[33] = InvalidSymbolTestCase("");
        return cases;
    }

    function tableInvalidSymbolsTest(InvalidSymbolTestCase memory invalidSymbols) public {
        vm.expectRevert(ITrendCoinErrors.InvalidTickerCharacters.selector);
        factory.deployTrendCoin(invalidSymbols.symbol, address(0), "");
    }

    function test_deployTrendCoin_validSymbols_withSpaces() public {
        (address coin1, ) = factory.deployTrendCoin("TEST COIN", address(0), "");
        assertTrue(coin1 != address(0), "Coin with space in middle should deploy");

        (address coin2, ) = factory.deployTrendCoin(" TEST ", address(0), "");
        assertTrue(coin2 != address(0), "Coin with leading and trailing spaces should deploy");

        (address coin3, ) = factory.deployTrendCoin("TEST COIN 123", address(0), "");
        assertTrue(coin3 != address(0), "Coin with multiple spaces should deploy");
    }

    function test_deployTrendCoin_validSymbols_lettersAndNumbers() public {
        (address coin1, ) = factory.deployTrendCoin("TEST123", address(0), "");
        assertTrue(coin1 != address(0), "Coin with letters then numbers should deploy");

        (address coin2, ) = factory.deployTrendCoin("123TEST", address(0), "");
        assertTrue(coin2 != address(0), "Coin with numbers then letters should deploy");

        (address coin3, ) = factory.deployTrendCoin("T1E2S3T", address(0), "");
        assertTrue(coin3 != address(0), "Coin with alternating letters and numbers should deploy");
    }

    function test_deployTrendCoin_validSymbols_lettersAndDash() public {
        (address coin1, ) = factory.deployTrendCoin("TEST-COIN", address(0), "");
        assertTrue(coin1 != address(0), "Coin with dash in middle should deploy");

        (address coin2, ) = factory.deployTrendCoin("-TEST-", address(0), "");
        assertTrue(coin2 != address(0), "Coin with leading and trailing dashes should deploy");

        (address coin3, ) = factory.deployTrendCoin("TEST--COIN", address(0), "");
        assertTrue(coin3 != address(0), "Coin with multiple dashes should deploy");
    }

    function test_deployTrendCoin_validSymbols_allTypes() public {
        (address coin1, ) = factory.deployTrendCoin("TEST-123 Coin", address(0), "");
        assertTrue(coin1 != address(0), "Coin with all character types should deploy");

        (address coin2, ) = factory.deployTrendCoin("ABC 123-XYZ", address(0), "");
        assertTrue(coin2 != address(0), "Coin with mixed valid characters should deploy");

        (address coin3, ) = factory.deployTrendCoin("Test-456 Coin 789", address(0), "");
        assertTrue(coin3 != address(0), "Coin with complex valid pattern should deploy");
    }

    // ============ Fee Distribution Tests ============

    function _deployTrendCoin() internal {
        string memory symbol = "FEETEST";
        (address coinAddress, ) = factory.deployTrendCoin(symbol, address(0), "");
        trendCoin = TrendCoin(coinAddress);
        vm.label(address(trendCoin), "TEST_TREND_COIN");
    }

    function _estimateLpFees(bytes memory commands, bytes[] memory inputs) internal returns (FeeEstimatorHook.FeeEstimatorState memory feeState) {
        uint256 snapshot = vm.snapshotState();
        _deployFeeEstimatorHook(address(hook));

        // Execute the swap
        uint256 deadline = block.timestamp + 20;
        router.execute(commands, inputs, deadline);

        feeState = FeeEstimatorHook(payable(address(hook))).getFeeState();

        vm.revertToState(snapshot);
    }

    function _recordZoraBalances() internal view returns (RewardBalances memory balances) {
        // For TrendCoins: creator and platformReferrer are address(0), so those balances will be 0
        balances.creator = 0; // No creator for trend coins
        balances.platformReferrer = 0; // No platform referrer for trend coins
        balances.tradeReferrer = 0; // We'll track this if provided
        balances.protocol = zoraToken.balanceOf(trendCoin.protocolRewardRecipient());
        balances.doppler = zoraToken.balanceOf(trendCoin.dopplerFeeRecipient());
    }

    function _buyTrendCoin(uint128 amountIn) internal returns (uint256 feeCurrency) {
        deal(address(zoraToken), users.buyer, amountIn);

        vm.warp(block.timestamp + 1 days);

        vm.startPrank(users.buyer);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), address(zoraToken), uint128(amountIn), uint48(block.timestamp + 1 days));

        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            address(zoraToken),
            uint128(amountIn),
            address(trendCoin),
            0,
            trendCoin.getPoolKey(),
            bytes("") // No trade referrer
        );

        // Estimate the total fees before executing
        FeeEstimatorHook.FeeEstimatorState memory feeState = _estimateLpFees(commands, inputs);

        feeCurrency = feeState.afterSwapCurrencyAmount;

        router.execute(commands, inputs, block.timestamp + 1 days);
        vm.stopPrank();
    }

    /// @notice Test that TrendCoin fee distribution gives 80% to protocol (Zora) and 20% to LP
    /// For TrendCoins, 100% of market rewards (80% of total fees) should go to protocol
    function test_trendCoin_feeDistribution_80PercentToProtocol() public {
        _deployTrendCoin();

        // Roll forward past the launch fee period (10 seconds) to avoid high launch fees
        // Launch fee starts at 99% and decays to 1% over 10 seconds
        vm.warp(block.timestamp + 11 seconds);

        uint128 tradeAmount = 1000 ether; // 1000 ZORA tokens

        // Record initial protocol balance
        address protocolRecipient = trendCoin.protocolRewardRecipient();
        uint256 initialProtocolBalance = zoraToken.balanceOf(protocolRecipient);

        // Perform trade (note: _buyTrendCoin also does vm.warp but this makes explicit we're past launch)
        _buyTrendCoin(tradeAmount);

        // Calculate final protocol balance
        uint256 finalProtocolBalance = zoraToken.balanceOf(protocolRecipient);
        uint256 protocolReward = finalProtocolBalance - initialProtocolBalance;

        // Fee breakdown for TrendCoins after launch period:
        // - Total fee: 1% (LP_FEE_V4 = 10,000 pips = 1%)
        // - LP reward: 20% of fees (LP_REWARD_BPS = 2000)
        // - Market rewards: 80% of fees
        // - For TrendCoins: protocol gets 100% of market rewards
        //
        // Expected calculation:
        // - Total fees = tradeAmount * 1% = 10 ZORA
        // - LP gets = 10 ZORA * 20% = 2 ZORA (minted as new LP positions)
        // - Market rewards = 10 ZORA * 80% = 8 ZORA
        // - Protocol receives = 8 ZORA (100% of market rewards for TrendCoins)
        uint256 expectedTotalFees = (uint256(tradeAmount) * CoinConstants.LP_FEE_V4) / 1_000_000;
        uint256 expectedMarketRewards = (expectedTotalFees * (10_000 - CoinConstants.LP_REWARD_BPS)) / 10_000;

        // Protocol should receive approximately all market rewards (allowing small rounding tolerance)
        assertApproxEqRel(protocolReward, expectedMarketRewards, 0.01e18, "Protocol should receive ~80% of total fees");

        // Verify actual value is reasonable (should be ~8 ZORA for 1000 ZORA trade)
        assertGt(protocolReward, 7.9 ether, "Protocol reward should be > 7.9 ZORA");
        assertLt(protocolReward, 8.1 ether, "Protocol reward should be < 8.1 ZORA");

        // Verify TrendCoin recipients are correctly configured (no creator/referrer rewards)
        assertEq(trendCoin.payoutRecipient(), address(0), "Payout recipient should be zero");
        assertEq(trendCoin.platformReferrer(), address(0), "Platform referrer should be zero");
    }

    /// @notice Test that TrendCoin has correct coin type
    function test_trendCoin_coinType() public {
        _deployTrendCoin();

        IHasCoinType.CoinType theCoinType = CoinRewardsV4.getCoinType(IHasRewardsRecipients(address(trendCoin)));
        assertEq(uint8(theCoinType), uint8(IHasCoinType.CoinType.Trend), "Should be Trend coin type");
    }

    /// @notice Test that TrendCoin recipients return expected values
    function test_trendCoin_rewardRecipients() public {
        _deployTrendCoin();

        // Payout recipient and platform referrer should be address(0)
        assertEq(trendCoin.payoutRecipient(), address(0), "Payout recipient should be zero");
        assertEq(trendCoin.platformReferrer(), address(0), "Platform referrer should be zero");

        // Protocol reward recipient should be set
        assertTrue(trendCoin.protocolRewardRecipient() != address(0), "Protocol recipient should be set");

        // Doppler fee recipient should be set
        assertTrue(trendCoin.dopplerFeeRecipient() != address(0), "Doppler recipient should be set");
    }

    // ============ Zero Fee After Launch Tests ============

    /// @notice TrendCoins should have 0 swap fee after the launch fee duration
    /// forge-config: default.isolate = true
    function test_trendCoin_zeroFeeAfterLaunchDuration() public {
        _deployTrendCoin();

        uint128 amountIn = 100 ether;
        address trader = makeAddr("trader");

        // Snapshot at same pool state for both swaps
        uint256 snapshot = vm.snapshotState();

        // Swap right at the end of launch period (still 1% LP fee for non-trend coins, but 0 for trend)
        vm.warp(block.timestamp + CoinConstants.LAUNCH_FEE_DURATION);
        deal(address(zoraToken), trader, amountIn);
        vm.startPrank(trader);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), address(zoraToken), amountIn, uint48(block.timestamp + 1 days));
        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            address(zoraToken), amountIn, address(trendCoin), 0, trendCoin.getPoolKey(), bytes("")
        );
        router.execute(commands, inputs, block.timestamp + 1 days);
        vm.stopPrank();
        uint256 coinsAtDuration = trendCoin.balanceOf(trader);

        vm.revertToState(snapshot);

        // Swap well after launch period — should yield same amount (both 0 fee)
        vm.warp(block.timestamp + CoinConstants.LAUNCH_FEE_DURATION + 1 days);
        deal(address(zoraToken), trader, amountIn);
        vm.startPrank(trader);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), address(zoraToken), amountIn, uint48(block.timestamp + 1 days));
        (commands, inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            address(zoraToken), amountIn, address(trendCoin), 0, trendCoin.getPoolKey(), bytes("")
        );
        router.execute(commands, inputs, block.timestamp + 1 days);
        vm.stopPrank();
        uint256 coinsAfterDuration = trendCoin.balanceOf(trader);

        // Both should be approximately equal (0% fee in both cases, same pool state)
        assertApproxEqRel(coinsAtDuration, coinsAfterDuration, 0.01e18, "both swaps should yield same coins at 0 fee");
    }

    /// @notice TrendCoins should still have the launch fee during the launch period
    /// forge-config: default.isolate = true
    function test_trendCoin_launchFeeStillAppliesDuringLaunch() public {
        _deployTrendCoin();

        uint128 amountIn = 100 ether;
        address trader = makeAddr("trader");

        uint256 snapshot = vm.snapshotState();

        // Swap immediately (launch fee ~99%)
        deal(address(zoraToken), trader, amountIn);
        vm.startPrank(trader);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), address(zoraToken), amountIn, uint48(block.timestamp + 1 days));
        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            address(zoraToken), amountIn, address(trendCoin), 0, trendCoin.getPoolKey(), bytes("")
        );
        router.execute(commands, inputs, block.timestamp + 1 days);
        vm.stopPrank();
        uint256 coinsAtLaunch = trendCoin.balanceOf(trader);

        vm.revertToState(snapshot);

        // Swap after launch period (0% fee for trend coins)
        vm.warp(block.timestamp + CoinConstants.LAUNCH_FEE_DURATION + 1);
        deal(address(zoraToken), trader, amountIn);
        vm.startPrank(trader);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), address(zoraToken), amountIn, uint48(block.timestamp + 1 days));
        (commands, inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            address(zoraToken), amountIn, address(trendCoin), 0, trendCoin.getPoolKey(), bytes("")
        );
        router.execute(commands, inputs, block.timestamp + 1 days);
        vm.stopPrank();
        uint256 coinsPostLaunch = trendCoin.balanceOf(trader);

        // Post-launch (0% fee) should yield significantly more coins than during launch (~99% fee)
        assertGt(coinsPostLaunch, coinsAtLaunch, "should receive more coins after launch fee ends");
    }

    /// @notice Test that TrendCoin uses correct production curve configuration
    function test_trendCoin_curveConfiguration() public {
        // Deploy a trend coin
        factory.deployTrendCoin("CURVETEST", address(0), "");

        // Decode the production pool config
        (
            uint8 version,
            address currency,
            int24[] memory tickLower,
            int24[] memory tickUpper,
            uint16[] memory numDiscoveryPositions,
            uint256[] memory maxDiscoverySupplyShare
        ) = CoinConfigurationVersions.decodeDopplerMultiCurveUniV4(CoinConstants.TREND_COIN_DEFAULT_POOL_CONFIG);

        // Verify version is 4 (Doppler Multi-Curve Uni V4)
        assertEq(version, 4, "Version should be 4");

        // Verify currency is ZORA
        assertEq(currency, CoinConstants.CREATOR_COIN_CURRENCY, "Currency should be ZORA");

        // Verify 3 curves
        assertEq(tickLower.length, 3, "Should have 3 curves");
        assertEq(tickUpper.length, 3, "Should have 3 curves");
        assertEq(numDiscoveryPositions.length, 3, "Should have 3 curves");
        assertEq(maxDiscoverySupplyShare.length, 3, "Should have 3 curves");

        // Verify Curve 1: ticks [-89200, -75200], 11 positions, 5% max supply
        assertEq(tickLower[0], -89200, "Curve 1 lower tick should be -89200");
        assertEq(tickUpper[0], -75200, "Curve 1 upper tick should be -75200");
        assertEq(numDiscoveryPositions[0], 11, "Curve 1 should have 11 positions");
        assertEq(maxDiscoverySupplyShare[0], 0.05e18, "Curve 1 max supply should be 5%");

        // Verify Curve 2: ticks [-77200, -68200], 11 positions, 12.5% max supply
        assertEq(tickLower[1], -77200, "Curve 2 lower tick should be -77200");
        assertEq(tickUpper[1], -68200, "Curve 2 upper tick should be -68200");
        assertEq(numDiscoveryPositions[1], 11, "Curve 2 should have 11 positions");
        assertEq(maxDiscoverySupplyShare[1], 0.125e18, "Curve 2 max supply should be 12.5%");

        // Verify Curve 3: ticks [-71200, -68200], 11 positions, 20% max supply
        assertEq(tickLower[2], -71200, "Curve 3 lower tick should be -71200");
        assertEq(tickUpper[2], -68200, "Curve 3 upper tick should be -68200");
        assertEq(numDiscoveryPositions[2], 11, "Curve 3 should have 11 positions");
        assertEq(maxDiscoverySupplyShare[2], 0.20e18, "Curve 3 max supply should be 20%");
    }

    // ============ Post-Deploy Hook Tests ============

    function test_deployTrendCoin_withNullHook() public {
        string memory symbol = "NULLHOOK";

        // Deploy with null hook (backward compatible behavior)
        (address coinAddress, bytes memory hookDataOut) = factory.deployTrendCoin(symbol, address(0), "");

        // Verify coin was created
        assertTrue(coinAddress != address(0), "Coin should be created");
        assertEq(hookDataOut.length, 0, "Hook data should be empty");

        // Verify TrendCoin properties
        TrendCoin coin = TrendCoin(payable(coinAddress));
        assertEq(coin.symbol(), symbol, "Symbol should match");
        assertEq(uint8(coin.coinType()), uint8(IHasCoinType.CoinType.Trend), "Should be Trend coin type");
    }

    function test_revertWhen_deployTrendCoin_ethWithoutHook() public {
        string memory symbol = "ETHERROR";

        // Should revert when sending ETH without hook
        vm.expectRevert(IZoraFactory.EthTransferInvalid.selector);
        factory.deployTrendCoin{value: 1 ether}(symbol, address(0), "");
    }

    function test_revertWhen_deployTrendCoin_invalidHook() public {
        string memory symbol = "BADHOOK";

        // Create invalid hook (EOA without code doesn't implement IHasAfterCoinDeploy)
        address invalidHook = makeAddr("invalidHook");

        vm.expectRevert();
        factory.deployTrendCoin{value: 1 ether}(symbol, invalidHook, "");
    }

    function test_revertWhen_deployTrendCoin_tickerAlreadyUsedWithHook() public {
        string memory symbol = "DUPLICATE";

        // Deploy first coin without hook
        factory.deployTrendCoin(symbol, address(0), "");

        // Try to deploy with same ticker - should revert even with hook address
        vm.expectRevert(abi.encodeWithSelector(ITrendCoinErrors.TickerAlreadyUsed.selector, symbol));
        factory.deployTrendCoin(symbol, makeAddr("someHook"), "");
    }

    function test_deployTrendCoin_addressPredictionWithHooks() public {
        string memory symbol = "PREDICT2";

        // Get predicted address (should work regardless of hook params)
        address predictedAddress = factory.trendCoinAddress(symbol);

        // Deploy with non-null hook address (but still null since no valid hook implementation)
        (address actualAddress, ) = factory.deployTrendCoin(symbol, address(0), "");

        // Prediction should still match (address based on ticker only)
        assertEq(actualAddress, predictedAddress, "Predicted address should match");
    }

    function test_deployTrendCoin_tickerUniquenessWithHooks() public {
        // Deploy with null hook
        factory.deployTrendCoin("test", address(0), "");

        // Try to deploy with same ticker, different case - should revert
        vm.expectRevert(abi.encodeWithSelector(ITrendCoinErrors.TickerAlreadyUsed.selector, "TEST"));
        factory.deployTrendCoin("TEST", address(0), "");

        // Try with mixed case - should also revert
        vm.expectRevert(abi.encodeWithSelector(ITrendCoinErrors.TickerAlreadyUsed.selector, "TeSt"));
        factory.deployTrendCoin("TeSt", address(0), "");
    }

    // ============ URI Encoding Tests ============

    function test_deployTrendCoin_uriEncoding_singleSpace() public {
        string memory symbol = "TEST COIN";
        (address coinAddress, ) = factory.deployTrendCoin(symbol, address(0), "");

        trendCoin = TrendCoin(coinAddress);
        string memory uri = trendCoin.tokenURI();

        // URI should have space converted to +
        assertTrue(keccak256(bytes(uri)) == keccak256(bytes("https://trends.theme.wtf/trend/TEST+COIN")), "URI should have space converted to +");
    }

    function test_deployTrendCoin_uriEncoding_multipleSpaces() public {
        string memory symbol = "TEST COIN 123";
        (address coinAddress, ) = factory.deployTrendCoin(symbol, address(0), "");

        trendCoin = TrendCoin(coinAddress);
        string memory uri = trendCoin.tokenURI();

        // URI should have all spaces converted to +
        assertTrue(keccak256(bytes(uri)) == keccak256(bytes("https://trends.theme.wtf/trend/TEST+COIN+123")), "URI should have all spaces converted to +");
    }

    function test_deployTrendCoin_uriEncoding_consecutiveSpaces() public {
        string memory symbol = "TEST  COIN";
        (address coinAddress, ) = factory.deployTrendCoin(symbol, address(0), "");

        trendCoin = TrendCoin(coinAddress);
        string memory uri = trendCoin.tokenURI();

        // URI should have consecutive spaces converted to consecutive +
        assertTrue(
            keccak256(bytes(uri)) == keccak256(bytes("https://trends.theme.wtf/trend/TEST++COIN")),
            "URI should have consecutive spaces converted to consecutive +"
        );
    }

    function test_deployTrendCoin_uriEncoding_leadingTrailingSpaces() public {
        string memory symbol = " TEST ";
        (address coinAddress, ) = factory.deployTrendCoin(symbol, address(0), "");

        trendCoin = TrendCoin(coinAddress);
        string memory uri = trendCoin.tokenURI();

        // URI should have leading and trailing spaces converted to +
        assertTrue(
            keccak256(bytes(uri)) == keccak256(bytes("https://trends.theme.wtf/trend/+TEST+")),
            "URI should have leading and trailing spaces converted to +"
        );
    }

    function test_deployTrendCoin_uriEncoding_noSpaces_unchanged() public {
        string memory symbol = "TESTCOIN";
        (address coinAddress, ) = factory.deployTrendCoin(symbol, address(0), "");

        trendCoin = TrendCoin(coinAddress);
        string memory uri = trendCoin.tokenURI();

        // URI should be unchanged when no spaces
        assertTrue(keccak256(bytes(uri)) == keccak256(bytes("https://trends.theme.wtf/trend/TESTCOIN")), "URI should be unchanged when symbol has no spaces");
    }

    function test_deployTrendCoin_uriEncoding_preservesSymbol() public {
        string memory symbol = "TEST COIN";
        (address coinAddress, ) = factory.deployTrendCoin(symbol, address(0), "");

        trendCoin = TrendCoin(coinAddress);

        // Symbol should remain unchanged (only URI is encoded)
        assertEq(trendCoin.symbol(), symbol, "Symbol should remain unchanged");
        assertEq(trendCoin.name(), symbol, "Name should remain unchanged");

        // URI should have space converted to +
        string memory uri = trendCoin.tokenURI();
        assertTrue(keccak256(bytes(uri)) == keccak256(bytes("https://trends.theme.wtf/trend/TEST+COIN")), "URI should have space converted to +");
    }

    // ============ Metadata Manager Tests ============

    function test_setContractURI_byMetadataManager() public {
        _deployTrendCoin();

        string memory newURI = "https://example.com/updated-metadata";

        // Metadata manager should be able to update the contract URI
        vm.prank(users.metadataManager);
        trendCoin.setContractURI(newURI);

        assertEq(trendCoin.contractURI(), newURI, "Contract URI should be updated");
    }

    function test_setContractURI_multipleUpdates() public {
        _deployTrendCoin();

        string memory uri1 = "https://example.com/v1";
        string memory uri2 = "https://example.com/v2";
        string memory uri3 = "https://example.com/v3";

        vm.startPrank(users.metadataManager);

        trendCoin.setContractURI(uri1);
        assertEq(trendCoin.contractURI(), uri1, "Contract URI should be v1");

        trendCoin.setContractURI(uri2);
        assertEq(trendCoin.contractURI(), uri2, "Contract URI should be v2");

        trendCoin.setContractURI(uri3);
        assertEq(trendCoin.contractURI(), uri3, "Contract URI should be v3");

        vm.stopPrank();
    }

    function test_revertWhen_setContractURI_byNonMetadataManager() public {
        _deployTrendCoin();

        string memory newURI = "https://example.com/malicious";

        // Random address should not be able to update the contract URI
        address randomUser = makeAddr("randomUser");
        vm.prank(randomUser);
        vm.expectRevert(ITrendCoin.OnlyMetadataManager.selector);
        trendCoin.setContractURI(newURI);
    }

    function test_revertWhen_setContractURI_byOwner() public {
        _deployTrendCoin();

        string memory newURI = "https://example.com/owner-attempt";

        // Even the coin owner should not be able to use setContractURI (must use setContractURI)
        vm.prank(users.creator);
        vm.expectRevert(ITrendCoin.OnlyMetadataManager.selector);
        trendCoin.setContractURI(newURI);
    }

    function test_revertWhen_setContractURI_byFactoryOwner() public {
        _deployTrendCoin();

        string memory newURI = "https://example.com/factory-owner-attempt";

        // Factory owner should not be able to update the contract URI
        vm.prank(users.factoryOwner);
        vm.expectRevert(ITrendCoin.OnlyMetadataManager.selector);
        trendCoin.setContractURI(newURI);
    }

    function test_setContractURI_emptyString() public {
        _deployTrendCoin();

        // Metadata manager should be able to set empty URI
        vm.prank(users.metadataManager);
        trendCoin.setContractURI("");

        assertEq(trendCoin.contractURI(), "", "Contract URI should be empty");
    }

    // ============ setNameAndSymbol Metadata Manager Tests ============

    function test_setNameAndSymbol_byMetadataManager() public {
        _deployTrendCoin();

        string memory newName = "UpdatedTrend";
        string memory newSymbol = "UPDTREND";

        vm.prank(users.metadataManager);
        trendCoin.setNameAndSymbol(newName, newSymbol);

        assertEq(trendCoin.name(), newName, "Name should be updated");
        assertEq(trendCoin.symbol(), newSymbol, "Symbol should be updated");
    }

    function test_setNameAndSymbol_multipleUpdates() public {
        _deployTrendCoin();

        vm.startPrank(users.metadataManager);

        trendCoin.setNameAndSymbol("Name1", "SYM1");
        assertEq(trendCoin.name(), "Name1", "Name should be Name1");
        assertEq(trendCoin.symbol(), "SYM1", "Symbol should be SYM1");

        trendCoin.setNameAndSymbol("Name2", "SYM2");
        assertEq(trendCoin.name(), "Name2", "Name should be Name2");
        assertEq(trendCoin.symbol(), "SYM2", "Symbol should be SYM2");

        vm.stopPrank();
    }

    function test_setNameAndSymbol_emitsEvent() public {
        _deployTrendCoin();

        string memory newName = "EventTrend";
        string memory newSymbol = "EVTTREND";

        vm.prank(users.metadataManager);
        vm.expectEmit(true, true, true, true);
        emit ICoin.NameAndSymbolUpdated(users.metadataManager, newName, newSymbol);
        trendCoin.setNameAndSymbol(newName, newSymbol);
    }

    function test_revertWhen_setNameAndSymbol_byNonMetadataManager() public {
        _deployTrendCoin();

        address randomUser = makeAddr("randomUser");
        vm.prank(randomUser);
        vm.expectRevert(ITrendCoin.OnlyMetadataManager.selector);
        trendCoin.setNameAndSymbol("Malicious", "MAL");
    }

    function test_revertWhen_setNameAndSymbol_byOwner() public {
        _deployTrendCoin();

        vm.prank(users.creator);
        vm.expectRevert(ITrendCoin.OnlyMetadataManager.selector);
        trendCoin.setNameAndSymbol("OwnerAttempt", "OWN");
    }

    function test_revertWhen_setNameAndSymbol_byFactoryOwner() public {
        _deployTrendCoin();

        vm.prank(users.factoryOwner);
        vm.expectRevert(ITrendCoin.OnlyMetadataManager.selector);
        trendCoin.setNameAndSymbol("FactoryAttempt", "FAC");
    }

    function test_revertWhen_setNameAndSymbol_emptyName() public {
        _deployTrendCoin();

        vm.prank(users.metadataManager);
        vm.expectRevert(abi.encodeWithSelector(ICoin.NameIsRequired.selector));
        trendCoin.setNameAndSymbol("", "SYM");
    }

    // ============ Pool Config Admin Tests ============

    function _getDefaultPoolConfigParams()
        internal
        pure
        returns (
            address currency,
            int24[] memory tickLower,
            int24[] memory tickUpper,
            uint16[] memory numDiscoveryPositions,
            uint256[] memory maxDiscoverySupplyShare
        )
    {
        (, currency, tickLower, tickUpper, numDiscoveryPositions, maxDiscoverySupplyShare) = CoinConfigurationVersions.decodeDopplerMultiCurveUniV4(
            CoinConstants.TREND_COIN_DEFAULT_POOL_CONFIG
        );
    }

    function test_setTrendCoinPoolConfig_ownerCanSet() public {
        bytes memory expectedPoolConfig = CoinConstants.TREND_COIN_DEFAULT_POOL_CONFIG;

        // Get the factory owner
        address factoryOwner = ZoraFactoryImpl(address(factory)).owner();

        (
            address currency,
            int24[] memory tickLower,
            int24[] memory tickUpper,
            uint16[] memory numDiscoveryPositions,
            uint256[] memory maxDiscoverySupplyShare
        ) = _getDefaultPoolConfigParams();

        vm.prank(factoryOwner);
        factory.setTrendCoinPoolConfig(currency, tickLower, tickUpper, numDiscoveryPositions, maxDiscoverySupplyShare);

        // Verify it was set
        bytes memory storedConfig = factory.trendCoinPoolConfig();
        assertEq(keccak256(storedConfig), keccak256(expectedPoolConfig), "Pool config should be stored");
    }

    function test_setTrendCoinPoolConfig_emitsEvent() public {
        bytes memory expectedPoolConfig = CoinConstants.TREND_COIN_DEFAULT_POOL_CONFIG;
        address factoryOwner = ZoraFactoryImpl(address(factory)).owner();

        (
            address currency,
            int24[] memory tickLower,
            int24[] memory tickUpper,
            uint16[] memory numDiscoveryPositions,
            uint256[] memory maxDiscoverySupplyShare
        ) = _getDefaultPoolConfigParams();

        vm.expectEmit(false, false, false, true);
        emit IZoraFactory.TrendCoinPoolConfigUpdated(expectedPoolConfig);

        vm.prank(factoryOwner);
        factory.setTrendCoinPoolConfig(currency, tickLower, tickUpper, numDiscoveryPositions, maxDiscoverySupplyShare);
    }

    function test_revertWhen_setTrendCoinPoolConfig_nonOwner() public {
        address nonOwner = makeAddr("nonOwner");

        (
            address currency,
            int24[] memory tickLower,
            int24[] memory tickUpper,
            uint16[] memory numDiscoveryPositions,
            uint256[] memory maxDiscoverySupplyShare
        ) = _getDefaultPoolConfigParams();

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        factory.setTrendCoinPoolConfig(currency, tickLower, tickUpper, numDiscoveryPositions, maxDiscoverySupplyShare);
    }

    function test_revertWhen_setTrendCoinPoolConfig_emptyArrays() public {
        address factoryOwner = ZoraFactoryImpl(address(factory)).owner();
        address currency = CoinConstants.CREATOR_COIN_CURRENCY;

        int24[] memory tickLower = new int24[](0);
        int24[] memory tickUpper = new int24[](0);
        uint16[] memory numDiscoveryPositions = new uint16[](0);
        uint256[] memory maxDiscoverySupplyShare = new uint256[](0);

        vm.prank(factoryOwner);
        vm.expectRevert(IZoraFactory.InvalidConfig.selector);
        factory.setTrendCoinPoolConfig(currency, tickLower, tickUpper, numDiscoveryPositions, maxDiscoverySupplyShare);
    }

    function test_revertWhen_setTrendCoinPoolConfig_mismatchedArrayLengths() public {
        address factoryOwner = ZoraFactoryImpl(address(factory)).owner();
        address currency = CoinConstants.CREATOR_COIN_CURRENCY;

        int24[] memory tickLower = new int24[](2);
        int24[] memory tickUpper = new int24[](3); // Mismatched length
        uint16[] memory numDiscoveryPositions = new uint16[](2);
        uint256[] memory maxDiscoverySupplyShare = new uint256[](2);

        vm.prank(factoryOwner);
        vm.expectRevert(IZoraFactory.InvalidConfig.selector);
        factory.setTrendCoinPoolConfig(currency, tickLower, tickUpper, numDiscoveryPositions, maxDiscoverySupplyShare);
    }

    function test_revertWhen_deployTrendCoin_configNotSet() public {
        // Deploy a fresh factory without pool config set
        // We need to test this with a fresh factory that hasn't had the config set
        // Since our test setup sets the config, we need to use a different approach

        // Deploy a new factory proxy
        address proxyShim = address(new ProxyShim());
        ZoraFactory newFactoryProxy = new ZoraFactory(proxyShim);

        // Create a new hook registry that includes the new factory as an owner
        ZoraHookRegistry newHookRegistry = new ZoraHookRegistry();
        address[] memory initialOwners = new address[](2);
        initialOwners[0] = address(this);
        initialOwners[1] = address(newFactoryProxy);
        newHookRegistry.initialize(initialOwners);

        // Create a new factory impl with the new hook registry
        ZoraFactoryImpl newFactoryImpl = new ZoraFactoryImpl(
            address(coinV4Impl),
            address(creatorCoinImpl),
            address(trendCoinImpl),
            address(hook),
            address(newHookRegistry)
        );

        // Upgrade to real impl and initialize
        UUPSUpgradeable(address(newFactoryProxy)).upgradeToAndCall(
            address(newFactoryImpl),
            abi.encodeWithSelector(ZoraFactoryImpl.initialize.selector, address(this))
        );

        IZoraFactory newFactory = IZoraFactory(address(newFactoryProxy));

        // Try to deploy trend coin without setting config first
        vm.expectRevert(IZoraFactory.TrendCoinPoolConfigNotSet.selector);
        newFactory.deployTrendCoin("NOCONFIG", address(0), "");
    }

    function test_deployTrendCoin_usesStoredConfig() public {
        // The factory should already have config set from setUp
        // Deploy a trend coin and verify it works
        string memory symbol = "CONFIGTEST";

        (address coinAddress, ) = factory.deployTrendCoin(symbol, address(0), "");

        // Verify the coin was created successfully
        trendCoin = TrendCoin(coinAddress);
        assertEq(trendCoin.symbol(), symbol, "Symbol should match");
        assertEq(uint8(trendCoin.coinType()), uint8(IHasCoinType.CoinType.Trend), "Should be Trend coin type");
    }

    function test_trendCoinPoolConfig_returnsStoredConfig() public {
        bytes memory expectedConfig = CoinConstants.TREND_COIN_DEFAULT_POOL_CONFIG;

        // Get stored config (should be set from setUp)
        bytes memory storedConfig = factory.trendCoinPoolConfig();

        assertEq(keccak256(storedConfig), keccak256(expectedConfig), "Should return the stored config");
    }
    // ============ Reinitialization Protection Tests ============

    function test_revertWhen_reinitializeTrendCoin() public {
        _deployTrendCoin();

        // Get pool key and configuration from the deployed coin
        ICoin coin = ICoin(address(trendCoin));
        PoolKey memory poolKey_ = coin.getPoolKey();
        PoolConfiguration memory poolConfig_ = coin.getPoolConfiguration();

        // Try to reinitialize via initializeTrendCoin - should fail
        address[] memory owners = new address[](1);
        owners[0] = users.creator;

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        trendCoin.initializeTrendCoin(owners, "REINIT", poolKey_, uint160(1 << 96), poolConfig_);
    }

    function test_revertWhen_legacyInitialize() public {
        _deployTrendCoin();

        // Get pool key and configuration from the deployed coin
        ICoin coin = ICoin(address(trendCoin));
        PoolKey memory poolKey_ = coin.getPoolKey();
        PoolConfiguration memory poolConfig_ = coin.getPoolConfiguration();

        // Try to call legacy initialize - should always revert with UseSpecificTrendCoinInitialize
        address[] memory owners = new address[](1);
        owners[0] = users.creator;

        vm.expectRevert(ITrendCoinErrors.UseSpecificTrendCoinInitialize.selector);
        trendCoin.initialize(
            address(0),
            owners,
            "https://example.com/reinit",
            "REINIT",
            "REINIT",
            address(0),
            CoinConstants.CREATOR_COIN_CURRENCY,
            poolKey_,
            uint160(1 << 96),
            poolConfig_
        );
    }
}
