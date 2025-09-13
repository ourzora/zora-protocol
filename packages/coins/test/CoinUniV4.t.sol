// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./utils/BaseTest.sol";
import {CoinConfigurationVersions} from "../src/libs/CoinConfigurationVersions.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {IV4Quoter} from "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LpPosition} from "../src/types/LpPosition.sol";
import {CoinCommon} from "../src/libs/CoinCommon.sol";
import {IZoraV4CoinHook} from "../src/interfaces/IZoraV4CoinHook.sol";
import {CoinConstants} from "../src/libs/CoinConstants.sol";
import {MarketConstants} from "../src/libs/MarketConstants.sol";
import {IMsgSender} from "../src/interfaces/IMsgSender.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {toBalanceDelta, BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {UniV4SwapHelper} from "../src/libs/UniV4SwapHelper.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {FeeEstimatorHook} from "./utils/FeeEstimatorHook.sol";
import {CoinRewardsV4} from "../src/libs/CoinRewardsV4.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolStateReader} from "../src/libs/PoolStateReader.sol";
import {CustomRevert} from "@uniswap/v4-core/src/libraries/CustomRevert.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {ICoin, IHasSwapPath, PathKey} from "../src/interfaces/ICoin.sol";
import {IDeployedCoinVersionLookup} from "../src/interfaces/IDeployedCoinVersionLookup.sol";

contract CoinUniV4Test is BaseTest {
    MockERC20 internal mockERC20A;
    MockERC20 internal mockERC20B;

    function setUp() public override {
        super.setUpWithBlockNumber(30267794);

        quoter = IV4Quoter(V4_QUOTER);
        mockERC20A = new MockERC20("MockERC20A", "MCKA");
        mockERC20B = new MockERC20("MockERC20B", "MCKB");

        // make sure the pool manager has some of the backing liquidity
        // so we can take the fees in the first swap
        mockERC20A.mint(address(poolManager), 1000000 ether);
        mockERC20B.mint(address(poolManager), 1000000 ether);
    }

    function _getCoinAddress(address currency, address createReferral, bytes32 salt) internal view returns (address) {
        return factory.coinAddress(users.creator, DEFAULT_NAME, DEFAULT_SYMBOL, _defaultPoolConfig(currency), createReferral, salt);
    }

    /// @dev Estimates the fees from a swap, by deploying a test hook that doesn't distribute the fees
    /// and then reverting the state after the swap
    function _estimateLpFees(bytes memory commands, bytes[] memory inputs) internal returns (FeeEstimatorHook.FeeEstimatorState memory feeState) {
        uint256 snapshot = vm.snapshot();
        _deployFeeEstimatorHook(address(hook));

        // Execute the swap
        uint256 deadline = block.timestamp + 20;
        router.execute(commands, inputs, deadline);

        feeState = FeeEstimatorHook(payable(address(hook))).getFeeState();

        vm.revertToState(snapshot);
    }

    /// and then reverting the state after the swap
    function _estimateSwap(
        bytes memory commands,
        bytes[] memory inputs
    ) internal returns (BalanceDelta delta, SwapParams memory swapParams, uint160 sqrtPriceX96) {
        uint256 snapshot = vm.snapshot();
        _deployFeeEstimatorHook(address(hook));

        // Execute the swap
        uint256 deadline = block.timestamp + 20;
        router.execute(commands, inputs, deadline);

        delta = FeeEstimatorHook(payable(address(hook))).getFeeState().lastDelta;
        swapParams = FeeEstimatorHook(payable(address(hook))).getFeeState().lastSwapParams;

        sqrtPriceX96 = PoolStateReader.getSqrtPriceX96(coinV4.getPoolKey(), poolManager);

        vm.revertToState(snapshot);
    }

    function test_setupZeroAddressForPoolManager() public {
        vm.expectRevert(ICoin.AddressZero.selector);
        new ContentCoin({
            protocolRewardRecipient_: address(0x1234),
            protocolRewards_: address(0x1234),
            poolManager_: IPoolManager(address(0)),
            airlock_: address(0)
        });
    }

    function test_deployContentCoin_verifyTotalSupplyAllocation() public {
        address currency = address(mockERC20A);
        _deployV4Coin(currency);

        // Verify total supply equals maximum allowed
        assertEq(coinV4.totalSupply(), CoinConstants.MAX_TOTAL_SUPPLY, "total supply");
        assertApproxEqAbs(coinV4.balanceOf(address(coinV4.poolManager())), MarketConstants.CONTENT_COIN_MARKET_SUPPLY, 1000, "pool launch supply");
        assertEq(coinV4.balanceOf(coinV4.payoutRecipient()), CoinConstants.CREATOR_LAUNCH_REWARD, "creator launch reward");
    }

    function test_estimateLpFees() public {
        address currency = address(mockERC20A);
        _deployV4Coin(currency);

        uint128 amountIn = uint128(0.00001 ether);
        uint128 minAmountOut = uint128(0);

        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            currency,
            amountIn,
            address(coinV4),
            minAmountOut,
            coinV4.getPoolKey(),
            bytes("")
        );

        address trader = makeAddr("trader");

        // mint some mockERC20 to the trader, so they can use it to buy the coin
        mockERC20A.mint(trader, 1 ether);

        // have trader approve to permit2
        vm.startPrank(trader);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), currency, type(uint128).max, uint48(block.timestamp + 1 days));
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), address(coinV4), type(uint128).max, uint48(block.timestamp + 1 days));

        // do a fake swap, so we can estimate LP fees
        FeeEstimatorHook.FeeEstimatorState memory feeState = _estimateLpFees(commands, inputs);

        bool isCoinToken0 = Currency.unwrap(coinV4.getPoolKey().currency0) == address(coinV4);
        uint128 feeCoin = isCoinToken0 ? feeState.fees0 : feeState.fees1;
        uint128 feeCurrency = isCoinToken0 ? feeState.fees1 : feeState.fees0;

        assertEq(feeCoin, 0, "fee coin should be 0");
        assertGt(feeCurrency, 0, "fee currency should be greater than to 0");
        assertGt(feeState.afterSwapCurrencyAmount, 0, "after swap fee currency should be greater than 0");

        // execute the swap
        router.execute(commands, inputs, block.timestamp + 20);

        // now estimate fees in swap back to currency
        (commands, inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            address(coinV4),
            feeCurrency,
            currency,
            minAmountOut,
            coinV4.getPoolKey(),
            bytes("")
        );

        FeeEstimatorHook.FeeEstimatorState memory newFeeState = _estimateLpFees(commands, inputs);

        uint128 newFeeCoin = isCoinToken0 ? newFeeState.fees0 : newFeeState.fees1;
        // uint128 newFeeCurrency = isCoinToken0 ? newFeeState.fees1 : newFeeState.fees0;

        assertGt(newFeeCoin, 0, "fee coin on second swap should be greater than 0");
        // assertGt(newFeeCurrency, 0, "fee currency on second swap should be greater than 0"); // TODO confirm what this should be -- prev was assertEq(0) and test passed but error message was asserting greater than 0
        assertGt(newFeeState.afterSwapCurrencyAmount, 0, "after swap fee currency on second swap should be greater than 0");
    }

    // Use the same constants as CoinRewardsV4.sol for consistency
    uint256 public constant CREATOR_REWARD_BPS = 6250; // 62.5% of market rewards (0.50% of total 1% fee)
    uint256 public constant CREATE_REFERRAL_REWARD_BPS = 2500; // 25% of market rewards (0.20% of total 1% fee)
    uint256 public constant TRADE_REFERRAL_REWARD_BPS = 500; // 5% of market rewards (0.04% of total 1% fee)
    uint256 public constant DOPPLER_REWARD_BPS = 125; // 1.25% of market rewards (0.01% of total 1% fee)

    struct Rewards {
        uint256 backing;
        uint256 doppler;
        uint256 createReferral;
        uint256 tradeReferral;
        uint256 protocol;
    }

    function computeExpectedRewards(uint256 fee, bool hasCreateReferral, bool hasTradeReferral) internal pure returns (Rewards memory rewards) {
        rewards.backing = CoinRewardsV4.calculateReward(fee, CREATOR_REWARD_BPS);
        rewards.doppler = CoinRewardsV4.calculateReward(fee, DOPPLER_REWARD_BPS);
        rewards.createReferral = hasCreateReferral ? CoinRewardsV4.calculateReward(fee, CREATE_REFERRAL_REWARD_BPS) : 0;
        rewards.tradeReferral = hasTradeReferral ? CoinRewardsV4.calculateReward(fee, TRADE_REFERRAL_REWARD_BPS) : 0;
        rewards.protocol = fee - rewards.backing - rewards.doppler - rewards.createReferral - rewards.tradeReferral;
    }

    function _estimateRewards(
        uint128 amountIn,
        address currencyIn,
        address currencyOut,
        bytes memory hookData,
        bool hasCreateReferral,
        bool hasTradeReferral
    ) internal returns (bytes memory commands, bytes[] memory inputs, Rewards memory rewards) {
        (commands, inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(currencyIn, amountIn, currencyOut, 0, coinV4.getPoolKey(), hookData);

        // do a fake swap, so we can estimate LP fees
        FeeEstimatorHook.FeeEstimatorState memory feeState = _estimateLpFees(commands, inputs);

        rewards = computeExpectedRewards(feeState.afterSwapCurrencyAmount, hasCreateReferral, hasTradeReferral);
    }

    function _estimateAndExecuteSwap(
        uint128 amountIn,
        address currencyIn,
        address currencyOut,
        bytes memory hookData,
        bool hasCreateReferral,
        bool hasTradeReferral
    ) internal returns (Rewards memory) {
        (bytes memory commands, bytes[] memory inputs, Rewards memory rewards) = _estimateRewards(
            amountIn,
            currencyIn,
            currencyOut,
            hookData,
            hasCreateReferral,
            hasTradeReferral
        );

        // Execute the swap
        router.execute(commands, inputs, block.timestamp + 20);

        return rewards;
    }

    function test_distributesMarketRewards(bool hasCreateReferral, bool hasTradeReferral) public {
        uint64 amountIn = 2 ether;
        address currency = address(mockERC20A);
        address createReferral = hasCreateReferral ? makeAddr("createReferral") : address(0);
        address tradeReferral = hasTradeReferral ? makeAddr("tradeReferral") : address(0);
        bytes32 salt = keccak256(abi.encodePacked(amountIn, hasCreateReferral, hasTradeReferral));
        _deployV4Coin(currency, createReferral, salt);

        uint256 balanceBeforePayoutRecipient = coinV4.balanceOf(coinV4.payoutRecipient());

        bytes memory hookData = hasTradeReferral ? abi.encode(tradeReferral) : bytes("");

        address trader = makeAddr("trader");

        // mint some mockERC20 to the trader, so they can use it to buy the coin
        mockERC20A.mint(trader, amountIn);

        vm.startPrank(trader);
        // have trader approve to permit2
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), currency, amountIn, uint48(block.timestamp + 1 days));

        Rewards memory totalRewards;

        // Swap 1: currency for coin
        Rewards memory rewards1 = _estimateAndExecuteSwap(uint128(amountIn), currency, address(coinV4), hookData, hasCreateReferral, hasTradeReferral);
        totalRewards.backing += rewards1.backing;
        totalRewards.doppler += rewards1.doppler;
        totalRewards.createReferral += rewards1.createReferral;
        totalRewards.tradeReferral += rewards1.tradeReferral;
        totalRewards.protocol += rewards1.protocol;

        // approve the coinV4 to spend the coin
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), address(coinV4), amountIn, uint48(block.timestamp + 1 days));

        // Swap 2: coin for currency
        Rewards memory rewards2 = _estimateAndExecuteSwap(uint128(amountIn), address(coinV4), currency, hookData, hasCreateReferral, hasTradeReferral);
        totalRewards.backing += rewards2.backing;
        totalRewards.doppler += rewards2.doppler;
        totalRewards.createReferral += rewards2.createReferral;
        totalRewards.tradeReferral += rewards2.tradeReferral;
        totalRewards.protocol += rewards2.protocol;

        vm.stopPrank();

        assertEq(coinV4.balanceOf(coinV4.payoutRecipient()) - balanceBeforePayoutRecipient, 0, "backing reward coin");
        assertEq(coinV4.balanceOf(coinV4.dopplerFeeRecipient()), 0, "doppler reward coin");
        if (hasCreateReferral) {
            assertEq(coinV4.balanceOf(createReferral), 0, "create referral reward coin");
        }
        if (hasTradeReferral) {
            assertEq(coinV4.balanceOf(tradeReferral), 0, "trade referral reward coin");
        }
        assertEq(coinV4.balanceOf(coinV4.protocolRewardRecipient()), 0, "protocol reward coin");

        assertApproxEqAbs(mockERC20A.balanceOf(coinV4.payoutRecipient()), totalRewards.backing, 5000, "backing reward currency");
        assertApproxEqAbs(mockERC20A.balanceOf(coinV4.dopplerFeeRecipient()), totalRewards.doppler, 5000, "doppler reward currency");
        if (hasCreateReferral) {
            assertApproxEqAbs(mockERC20A.balanceOf(createReferral), totalRewards.createReferral, 5000, "create referral reward currency");
        }
        if (hasTradeReferral) {
            assertApproxEqAbs(mockERC20A.balanceOf(tradeReferral), totalRewards.tradeReferral, 5000, "trade referral reward currency");
        }
        assertApproxEqAbs(mockERC20A.balanceOf(coinV4.protocolRewardRecipient()), totalRewards.protocol, 5000, "protocol reward currency");
    }

    function test_distributesMarketRewardsInEth() public {
        uint64 amountIn = 0.1 ether;

        // Use address(0) as currency to price the coin in ETH
        address currency = address(0);
        bytes32 salt = keccak256(abi.encodePacked("eth-rewards-test"));
        _deployV4Coin(currency, address(0), salt);

        address trader = makeAddr("trader");

        // Give trader ETH
        vm.deal(trader, amountIn);

        // Record initial ETH balance of payout recipient
        uint256 initialPayoutBalance = coinV4.payoutRecipient().balance;

        // Swap ETH for coin
        _swapSomeCurrencyForCoin(coinV4, currency, amountIn, trader);

        // Verify that rewards were paid out in ETH
        assertGt(coinV4.payoutRecipient().balance, initialPayoutBalance, "backing reward should be paid in ETH");
    }

    function test_canSwapEthForCoin(uint128 amountIn) public {
        vm.assume(amountIn > 0.00001 ether);
        vm.assume(amountIn < 1 ether);

        // Use address(0) as currency to price the coin in ETH
        address currency = address(0);
        bytes32 salt = keccak256(abi.encodePacked("eth-coin-test"));
        _deployV4Coin(currency, address(0), salt);

        address trader = makeAddr("trader");

        // Give trader ETH
        vm.deal(trader, amountIn);

        uint256 initialEthBalance = trader.balance;

        // Swap ETH for coin
        _swapSomeCurrencyForCoin(coinV4, currency, amountIn, trader);

        // Verify the swap worked
        assertEq(trader.balance, initialEthBalance - amountIn, "trader should have spent ETH");
        assertGt(coinV4.balanceOf(trader), 0, "trader should have received coin");

        // Now swap some coin back for ETH
        uint128 coinBalance = uint128(coinV4.balanceOf(trader));

        _swapSomeCoinForCurrency(coinV4, currency, coinBalance, trader);

        // Verify the reverse swap worked
        assertEq(coinV4.balanceOf(trader), 0, "trader should have no coins left");
        assertGt(trader.balance, 0, "trader should have received ETH back");
    }

    function test_swap_emitsCoinMarketRewardsV4() public {
        uint64 amountIn = 1 ether;
        address currency = address(mockERC20A);
        address createReferral = makeAddr("createReferral");
        address tradeReferral = makeAddr("tradeReferral");
        bytes32 salt = keccak256(abi.encode(bytes("randomSalt")));
        _deployV4Coin(currency, createReferral, salt);

        bytes memory hookData = abi.encode(tradeReferral);

        address trader = makeAddr("trader");

        // mint some mockERC20 to the trader, so they can use it to buy the coin
        mockERC20A.mint(trader, amountIn);

        // have trader approve to permit2
        vm.startPrank(trader);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), currency, amountIn, uint48(block.timestamp + 1 days));

        (bytes memory commands, bytes[] memory inputs, Rewards memory calculatedRewards) = _estimateRewards(
            uint128(amountIn),
            currency,
            address(coinV4),
            hookData,
            true,
            true
        );

        vm.expectEmit(true, true, true, true);
        emit IZoraV4CoinHook.CoinMarketRewardsV4(
            address(coinV4),
            address(mockERC20A),
            coinV4.payoutRecipient(),
            createReferral,
            tradeReferral,
            coinV4.protocolRewardRecipient(),
            coinV4.dopplerFeeRecipient(),
            IZoraV4CoinHook.MarketRewardsV4({
                creatorPayoutAmountCurrency: calculatedRewards.backing,
                creatorPayoutAmountCoin: 0,
                platformReferrerAmountCurrency: calculatedRewards.createReferral,
                platformReferrerAmountCoin: 0,
                tradeReferrerAmountCurrency: calculatedRewards.tradeReferral,
                tradeReferrerAmountCoin: 0,
                protocolAmountCurrency: calculatedRewards.protocol,
                protocolAmountCoin: 0,
                dopplerAmountCurrency: calculatedRewards.doppler,
                dopplerAmountCoin: 0
            })
        );

        // Execute the swap
        router.execute(commands, inputs, block.timestamp + 20);
        vm.stopPrank();
    }

    function test_canGetQuoteForSwappingCurrencyForCoin() public {
        address currency = address(mockERC20A);
        _deployV4Coin(currency);

        bool isCoinToken0 = CoinCommon.sortTokens(address(coinV4), currency);

        // we want to swap currency for coin
        bool zeroForOne = !isCoinToken0;

        IV4Quoter.QuoteExactSingleParams memory quoteParams = IV4Quoter.QuoteExactSingleParams({
            poolKey: coinV4.getPoolKey(),
            zeroForOne: zeroForOne,
            exactAmount: 1 ether,
            hookData: bytes("")
        });

        (uint256 amountOut, ) = quoter.quoteExactInputSingle(quoteParams);

        assertGt(amountOut, 0);
    }

    function _findCoinAddress(address currency, bool isCoinToken0) internal view returns (bytes32 salt, address coinAddress) {
        uint256 i = 0;

        while (true) {
            salt = bytes32(keccak256(abi.encode(i)));
            coinAddress = _getCoinAddress(currency, address(0), salt);
            bool coinIsToken0 = coinAddress < currency;
            if (coinIsToken0 == isCoinToken0) {
                break;
            }
            i++;
        }
    }

    function test_canSwapCurrencyForCoinCoinIsFirst(uint128 amountIn) public {
        vm.assume(amountIn > 0.00001 ether);
        vm.assume(amountIn < 10000000000000 ether);
        address currency = address(mockERC20A);

        (bytes32 salt, ) = _findCoinAddress(currency, true);

        _deployV4Coin(currency, address(0), salt);

        bool isCoinToken0 = CoinCommon.sortTokens(address(coinV4), currency);

        assertTrue(isCoinToken0);

        _testSwapCurrencyForCoin(currency, amountIn);
    }

    function test_canSwapCurrencyForCoinCoinIsSecond(uint128 amountIn) public {
        vm.assume(amountIn > 0.00001 ether);
        vm.assume(amountIn < 10000000000000 ether);

        // make a currency with a small number, that will always be less than the coin
        address currency = address(mockERC20A);

        (bytes32 salt, ) = _findCoinAddress(currency, false);

        _deployV4Coin(currency, address(0), salt);

        assertTrue(coinV4.getPoolKey().currency0 == Currency.wrap(currency));

        _testSwapCurrencyForCoin(currency, amountIn);
    }

    function _testSwapCurrencyForCoin(address currency, uint128 amountIn) private {
        uint128 minAmountOut = 0;

        MockERC20(currency).mint(address(poolManager), 100000000000000000000000000000 ether);

        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            currency,
            amountIn,
            address(coinV4),
            minAmountOut,
            coinV4.getPoolKey(),
            bytes("")
        );

        address trader = makeAddr("trader");

        // mint some mockERC20 to the trader, so they can use it to buy the coin
        mockERC20A.mint(trader, amountIn);

        // have trader approve to permit2
        vm.startPrank(trader);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), currency, amountIn, uint48(block.timestamp + 1 days));

        // Execute the swap
        uint256 deadline = block.timestamp + 20;
        router.execute(commands, inputs, deadline);

        assertEq(mockERC20A.balanceOf(trader), 0);
        assertGt(coinV4.balanceOf(trader), minAmountOut);
    }

    function test_canSwapCoinForCurrencyCoinIsFirst(uint128 amountIn) public {
        vm.assume(amountIn > 0.00001 ether);
        vm.assume(amountIn < 10000000000000 ether);

        address currency = address(mockERC20A);

        (bytes32 salt, ) = _findCoinAddress(currency, true);

        _deployV4Coin(currency, address(0), salt);
    }

    function test_canSwapCoinForCurrencyCoinIsSecond(uint128 amountIn) public {
        vm.assume(amountIn > 0.00001 ether);
        vm.assume(amountIn < 10000000000000 ether);

        address currency = address(mockERC20A);

        (bytes32 salt, ) = _findCoinAddress(currency, false);

        _deployV4Coin(currency, address(0), salt);
    }

    function _testSwapCoinForCurrency(address currency, uint128 currencyIn) private {
        address trader = makeAddr("trader");

        mockERC20A.mint(trader, currencyIn);

        // swap some currency for coin so that the pool has some balance to work with
        _swapSomeCurrencyForCoin(coinV4, currency, currencyIn, trader);

        uint128 coinIn = uint128(coinV4.balanceOf(trader));
        // now swap coin for currency
        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            address(coinV4),
            coinIn,
            currency,
            0,
            coinV4.getPoolKey(),
            bytes("")
        );

        vm.startPrank(trader);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), address(coinV4), coinIn, uint48(block.timestamp + 1 days));

        router.execute(commands, inputs, block.timestamp + 20);

        // do some more swaps back and forth
        _swapSomeCurrencyForCoin(coinV4, currency, uint128(IERC20(address(currency)).balanceOf(trader)), trader);

        // swap back to coin
        _swapSomeCoinForCurrency(coinV4, currency, uint128(IERC20(address(coinV4)).balanceOf(trader)), trader);
    }

    function testSwappingEmitsSwapEventFromSenderNoRevert() public {
        _callSwappingEmitsSwapEvent(false, false);
    }

    function testSwappingEmitsSwapEventFromSenderReverts() public {
        _callSwappingEmitsSwapEvent(false, true);
    }

    function testSwappingEmitsSwapEventFromTrustedMessageSenderNoRevert() public {
        _callSwappingEmitsSwapEvent(true, false);
    }

    function testSwappingEmitsSwapEventFromTrustedMessageSenderReverts() public {
        _callSwappingEmitsSwapEvent(true, true);
    }

    function test_afterInitializeRevertsWhenSenderIsNotACoin() public {
        // First deploy a coin so we have a valid hook to test against
        address currency = address(mockERC20A);
        _deployV4Coin(currency);

        // Deploy a mock contract that is not a coin
        MockERC20 notACoin = new MockERC20("NotACoin", "NAC");

        bool isCoinToken0 = CoinCommon.sortTokens(address(coinV4), address(notACoin));

        // Create a valid pool key
        PoolKey memory key = PoolKey({
            currency0: isCoinToken0 ? Currency.wrap(address(coinV4)) : Currency.wrap(address(notACoin)),
            currency1: isCoinToken0 ? Currency.wrap(address(notACoin)) : Currency.wrap(address(coinV4)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        // We need to prank the call to come from the non-coin contract
        vm.startPrank(address(notACoin));

        // The hook should revert with NotACoin error when initializing
        vm.expectRevert(
            abi.encodeWithSelector(
                CustomRevert.WrappedError.selector,
                address(hook),
                IHooks.afterInitialize.selector,
                abi.encodeWithSelector(IZoraV4CoinHook.NotACoin.selector, address(notACoin)),
                abi.encodeWithSelector(Hooks.HookCallFailed.selector)
            )
        );

        // Call the pool manager to initialize, the hook should revert because the calling coin is not a coin
        poolManager.initialize(key, uint160(1049428825694136384760392514097686388));

        vm.stopPrank();
    }

    function _callSwappingEmitsSwapEvent(bool swapIsFromTrustedMessageSender, bool trustedSenderReverts) internal {
        uint64 amountIn = uint64(0.1 ether);
        address currency = address(mockERC20A);
        _deployV4Coin(currency);

        uint128 minAmountOut = uint128(0);

        PoolKey memory key = coinV4.getPoolKey();

        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            currency,
            amountIn,
            address(coinV4),
            minAmountOut,
            key,
            bytes("")
        );

        address trader = makeAddr("trader");

        // mint some mockERC20 to the trader, so they can use it to buy the coin
        mockERC20A.mint(trader, amountIn);

        // have trader approve to permit2
        vm.startPrank(trader);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), currency, amountIn, uint48(block.timestamp + 1 days));

        // Execute the swap
        uint256 deadline = block.timestamp + 20;

        address sender = UNIVERSAL_ROUTER;

        (BalanceDelta delta, SwapParams memory swapParams, uint160 sqrtPriceX96) = _estimateSwap(commands, inputs);

        address[] memory _trustedMessageSenders = new address[](1);
        _trustedMessageSenders[0] = UNIVERSAL_ROUTER;

        // if we want to simulate swap happening from a non-trusted message sender, we copy the router code to a new address that isn't
        // trusted by the hook, and have that router execute the swap
        if (!swapIsFromTrustedMessageSender) {
            bytes memory routerCode = address(router).code;
            address targetAddr = makeAddr("targetAddr");
            vm.etch(targetAddr, routerCode);
            router = IUniversalRouter(targetAddr);
            // we need to approve the token again on the new router address.
            UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), currency, amountIn, uint48(block.timestamp + 1 days));
        }

        // if we want to simulate the trusted sender reverting, we mock the msgSender function on the router to revert
        if (trustedSenderReverts) {
            vm.mockCallRevert(address(router), abi.encodeWithSelector(IMsgSender.msgSender.selector), "any revert");
        }

        bool isCoinBuy = true;

        vm.expectEmit(false, true, true, true);
        emit IZoraV4CoinHook.Swapped(
            sender,
            trustedSenderReverts ? address(0) : trader,
            swapIsFromTrustedMessageSender,
            key,
            CoinCommon.hashPoolKey(key),
            swapParams,
            delta.amount0(),
            delta.amount1(),
            isCoinBuy,
            "",
            sqrtPriceX96
        );
        router.execute(commands, inputs, deadline);
    }

    function test_getSwapPath_whenBackingCurrencyIsErc20() public {
        address currency = address(mockERC20A);
        _deployV4Coin(currency);

        IHasSwapPath.PayoutSwapPath memory swapPath = coinV4.getPayoutSwapPath(IDeployedCoinVersionLookup(address(factory)));

        assertEq(swapPath.path.length, 1);
        _assertPathKeyEqual(
            swapPath.path[0],
            PathKey({
                intermediateCurrency: Currency.wrap(address(mockERC20A)),
                fee: coinV4.getPoolKey().fee,
                tickSpacing: coinV4.getPoolKey().tickSpacing,
                hooks: coinV4.getPoolKey().hooks,
                hookData: bytes("")
            }),
            "path key"
        );
    }

    function test_getSwapPath_whenBackingCurrencyProvidesPath() public {
        address zora = address(mockERC20A);
        ICoin backingCoin = _deployV4Coin(zora);
        // now create a final coin paired with the backing coin
        ICoin contentCoin = _deployV4Coin(address(backingCoin));

        PathKey[] memory path = contentCoin.getPayoutSwapPath(IDeployedCoinVersionLookup(address(factory))).path;

        // swap path should be:
        // 1. content coin -> backing coin
        // 2. backing coin -> zora coin
        assertEq(path.length, 2);
        _assertPathKeyEqual(
            path[0],
            PathKey({
                intermediateCurrency: Currency.wrap(address(backingCoin)),
                fee: contentCoin.getPoolKey().fee,
                tickSpacing: contentCoin.getPoolKey().tickSpacing,
                hooks: contentCoin.getPoolKey().hooks,
                hookData: bytes("")
            }),
            "content to backing coin"
        );
        _assertPathKeyEqual(
            path[1],
            PathKey({
                intermediateCurrency: Currency.wrap(zora),
                fee: backingCoin.getPoolKey().fee,
                tickSpacing: backingCoin.getPoolKey().tickSpacing,
                hooks: backingCoin.getPoolKey().hooks,
                hookData: bytes("")
            }),
            "backing to zora coin"
        );
    }

    function test_swap_withBackingCoinToZora_paysRewardsInZoraOnly(uint128 amountIn) public {
        // zora is a mock erc20
        address zora = address(mockERC20A);
        // make sure pool manager has enough zora in it so we can take the fees on the swap
        mockERC20A.mint(address(poolManager), 10000000000000000 ether);

        // backing coin is a mock coin that is paired with zora
        ICoin backingCoin = _deployV4Coin(zora);
        // now create a final coin paired with the backing coin
        ICoin contentCoin = _deployV4Coin(address(backingCoin));

        vm.assume(amountIn > 0.000000000001 ether);
        vm.assume(amountIn < 10000000000000000 ether);

        address trader = makeAddr("trader");
        MockERC20(zora).mint(trader, amountIn);

        address protocolRewardRecipient = contentCoin.protocolRewardRecipient();

        // swap some zora for backing coin, so the trader has some backing coin - this should not cause a multihop swap for rewards
        _swapSomeCurrencyForCoin(backingCoin, zora, uint128(IERC20(address(zora)).balanceOf(trader)), trader);

        // get balances before
        uint256 protocolRewardRecipientZoraBalanceBefore = IERC20(address(zora)).balanceOf(protocolRewardRecipient);
        uint256 protocolRewardRecipientBackingCoinBalanceBefore = IERC20(address(backingCoin)).balanceOf(protocolRewardRecipient);
        uint256 protocolRewardRecipientContentCoinBalanceBefore = IERC20(address(contentCoin)).balanceOf(protocolRewardRecipient);

        // swap some backing coin for content coin, this should do final rewards transfer in correct balance
        _swapSomeCurrencyForCoin(contentCoin, address(backingCoin), uint128(IERC20(address(backingCoin)).balanceOf(trader)), trader);

        // swap some content coin for backing coin, this should do final rewards transfer in correct balance
        _swapSomeCoinForCurrency(contentCoin, address(backingCoin), uint128(IERC20(address(contentCoin)).balanceOf(trader)), trader);

        // make sure that no zora, backing, or content coin was paid out to the protocol reward recipient, but just usdc was
        assertEq(IERC20(address(backingCoin)).balanceOf(protocolRewardRecipient), protocolRewardRecipientBackingCoinBalanceBefore, "backing coin was paid out");
        assertEq(IERC20(address(contentCoin)).balanceOf(protocolRewardRecipient), protocolRewardRecipientContentCoinBalanceBefore, "content coin was paid out");
        assertGt(IERC20(address(zora)).balanceOf(protocolRewardRecipient), protocolRewardRecipientZoraBalanceBefore, "zora was paid out");
    }

    function _assertPathKeyEqual(PathKey memory a, PathKey memory b, string memory keyName) internal pure {
        assertEq(Currency.unwrap(a.intermediateCurrency), Currency.unwrap(b.intermediateCurrency), string.concat(keyName, " intermediateCurrency"));
        assertEq(a.fee, b.fee, string.concat(keyName, " fee"));
        assertEq(a.tickSpacing, b.tickSpacing, string.concat(keyName, " tickSpacing"));
        assertEq(address(a.hooks), address(b.hooks), string.concat(keyName, " hooks"));
    }
}
