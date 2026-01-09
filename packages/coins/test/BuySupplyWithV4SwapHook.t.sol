// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseTest} from "./utils/BaseTest.sol";
import {BuySupplyWithV4SwapHook} from "../src/hooks/deployment/BuySupplyWithV4SwapHook.sol";
import {V3ToV4SwapLib} from "../src/libs/V3ToV4SwapLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CoinConfigurationVersions} from "../src/libs/CoinConfigurationVersions.sol";
import {ICoin} from "../src/interfaces/ICoin.sol";
import {ISwapRouter} from "../src/interfaces/ISwapRouter.sol";
import {CoinConstants} from "../src/libs/CoinConstants.sol";
import {ContentCoin} from "../src/ContentCoin.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {console} from "forge-std/console.sol";

contract BuySupplyWithV4SwapHookTest is BaseTest {
    address constant ZORA = 0x1111111111166b7FE7bd91427724B487980aFc69;
    BuySupplyWithV4SwapHook postDeployHook;

    // TODO: Add tests to verify swap path always goes from input currency to backing currency
    // 1. Test V3-only swap paths (e.g., USDC -> WETH -> Creator Coin)
    // 2. Test V4-only swap paths (e.g., WETH -> Creator Coin via V4)
    // 3. Test mixed V3->V4 swap paths (e.g., USDC -> WETH via V3, then WETH -> Creator Coin via V4)
    // 4. Test different input currencies (USDC, WETH, other ERC20s) all properly route to backing currency
    // 5. Verify the final currency received always matches the Content Coin's backing currency
    // 6. Clean up debug logging in BuySupplyWithV4SwapHook.sol

    function setUp() public override {
        super.setUpWithBlockNumber(33646532);

        postDeployHook = new BuySupplyWithV4SwapHook(factory, address(swapRouter), address(V4_POOL_MANAGER));
    }

    function _encodeV4HookData(
        address buyRecipient,
        bytes memory v3Route,
        PoolKey[] memory v4Route,
        address inputCurrency,
        uint256 inputAmount,
        uint256 minAmountOut
    ) internal pure returns (bytes memory) {
        BuySupplyWithV4SwapHook.InitialSupplyParams memory params = BuySupplyWithV4SwapHook.InitialSupplyParams({
            buyRecipient: buyRecipient,
            v3Route: v3Route,
            v4Route: v4Route,
            inputCurrency: inputCurrency,
            inputAmount: inputAmount,
            minAmountOut: minAmountOut
        });
        return abi.encode(params);
    }

    function _encodeV3Path(address tokenA, uint24 feeA, address tokenB, uint24 feeB, address tokenC) internal pure returns (bytes memory) {
        return abi.encodePacked(tokenA, feeA, tokenB, feeB, tokenC);
    }

    function _encodeV3PathSingle(address tokenA, uint24 fee, address tokenB) internal pure returns (bytes memory) {
        return abi.encodePacked(tokenA, fee, tokenB);
    }

    function _deployCreatorCoin(address payoutRecipient) internal returns (address creatorCoinAddress) {
        bytes memory creatorPoolConfig = CoinConfigurationVersions.defaultDopplerMultiCurveUniV4(ZORA);

        vm.prank(payoutRecipient);
        creatorCoinAddress = factory.deployCreatorCoin(
            payoutRecipient, // payoutRecipient
            _getDefaultOwners(), // owners
            "https://creator.com", // uri
            "Creator Coin", // name
            "CREATOR", // symbol
            creatorPoolConfig, // poolConfig (ZORA-backed)
            users.platformReferrer, // platformReferrer
            bytes32(0) // coinSalt
        );
    }

    function _deployContentCoinWithHook(
        address backingCurrency,
        uint256 payableAmount,
        address caller,
        bytes memory hookData
    ) internal returns (address coinAddress, uint256 amountCurrency, uint256 coinsPurchased) {
        bytes memory poolConfig = CoinConfigurationVersions.defaultDopplerMultiCurveUniV4(backingCurrency);

        vm.prank(caller);
        bytes memory hookDataOut;
        (coinAddress, hookDataOut) = factory.deployWithHook{value: payableAmount}(
            caller, // payoutRecipient
            _getDefaultOwners(), // owners
            "https://test.com", // uri
            "Content Coin", // name
            "CONTENT", // symbol
            poolConfig, // poolConfig
            users.platformReferrer, // platformReferrer
            address(postDeployHook), // postDeployHook
            hookData // postDeployHookData
        );

        (amountCurrency, coinsPurchased) = abi.decode(hookDataOut, (uint256, uint256));
    }

    /// @dev Test buying initial supply of a Content Coin backed by ZORA
    /// This only requires V3 swap (ETH -> ZORA) since the coin is already backed by ZORA
    function test_buyContentCoinSupply_V3SwapOnly() public {
        uint256 initialOrderSize = 0.1 ether;
        vm.deal(users.creator, initialOrderSize);

        // Create V3 path: ETH -> USDC -> ZORA
        bytes memory v3Route = _encodeV3Path(
            address(weth),
            3000, // WETH/USDC 0.3%
            USDC_ADDRESS,
            3000, // USDC/ZORA 0.3%
            ZORA
        );

        console.logBytes(v3Route);

        // No V4 route needed since coin is backed by ZORA
        PoolKey[] memory v4Route = new PoolKey[](0);

        bytes memory hookData = _encodeV4HookData(users.creator, v3Route, v4Route, address(0), initialOrderSize, 0);

        // Deploy Content Coin backed by ZORA
        (address coinAddress, uint256 amountCurrency, uint256 coinsPurchased) = _deployContentCoinWithHook(ZORA, initialOrderSize, users.creator, hookData);

        ContentCoin coin = ContentCoin(payable(coinAddress));

        // Verify the coin is properly configured
        assertEq(coin.currency(), ZORA, "Coin should be backed by ZORA");
        assertGt(amountCurrency, 0, "Should have received ZORA from V3 swap");
        assertGt(coinsPurchased, 0, "Should have purchased coins");

        // Creator should have their launch supply + purchased coins
        assertEq(
            coin.balanceOf(users.creator),
            CoinConstants.CONTENT_COIN_INITIAL_CREATOR_SUPPLY + coinsPurchased,
            "Creator should have launch supply + purchased coins"
        );

        // Verify V3 swap worked correctly (mock implementation returns positive values)
        // Note: In real implementation this would check actual pool liquidity
    }

    /// @dev Test that BuyInitialSupply event is emitted with accurate data using snapshot pattern
    function test_BuyInitialSupplyEvent() public {
        uint256 initialOrderSize = 0.1 ether;
        vm.deal(users.creator, initialOrderSize * 2); // Double to account for both runs

        // Create V3 path: ETH -> USDC -> ZORA
        bytes memory v3Route = _encodeV3Path(
            address(weth),
            3000, // WETH/USDC 0.3%
            USDC_ADDRESS,
            3000, // USDC/ZORA 0.3%
            ZORA
        );

        // No V4 route needed since coin is backed by ZORA
        PoolKey[] memory v4Route = new PoolKey[](0);

        bytes memory hookData = _encodeV4HookData(users.creator, v3Route, v4Route, address(0), initialOrderSize, 0);

        PoolKey[] memory expectedV4Route = new PoolKey[](1);

        // FIRST RUN: Use snapshot pattern to capture expected values
        uint256 snapshot = vm.snapshot();

        // Execute deployment to get actual values
        (address coinAddress, uint256 expectedAmountCurrency, uint256 expectedCoinsPurchased) = _deployContentCoinWithHook(
            ZORA,
            initialOrderSize,
            users.creator,
            hookData
        );

        expectedV4Route[0] = ICoin(payable(coinAddress)).getPoolKey();

        // Revert to snapshot to restore state
        vm.revertToState(snapshot);

        // SECOND RUN: Execute with event verification using captured values
        // Note: We skip checking coin address (first indexed param) since it will be different after snapshot revert
        vm.expectEmit(false, true, true, true); // Skip coin address, check recipient, coinsPurchased, and all data
        emit BuySupplyWithV4SwapHook.BuyInitialSupply(
            address(0), // coin (indexed) - skip checking since address will differ after revert
            users.creator, // recipient (indexed)
            expectedCoinsPurchased, // coinsPurchased (indexed)
            v3Route, // v3Route (data)
            expectedV4Route, // v4Route (data)
            address(0), // inputCurrency (data) - ETH represented as address(0)
            initialOrderSize, // inputAmount (data)
            expectedAmountCurrency // v4SwapInput (data) - amount received from V3 swap
        );

        // Deploy Content Coin backed by ZORA - this should emit event with matching parameters
        _deployContentCoinWithHook(ZORA, initialOrderSize, users.creator, hookData);
    }

    /// @dev Test buying initial supply of a Content Coin paired with ETH
    /// This requires no V3 or V4 routing - just direct V4 swap with ETH
    function test_buyContentCoinSupply_ETHPaired() public {
        uint256 initialOrderSize = 0.05 ether;
        vm.deal(users.creator, initialOrderSize);

        // No V3 route needed - direct ETH to coin swap
        bytes memory v3Route = "";

        // No V4 route needed - direct swap
        PoolKey[] memory v4Route = new PoolKey[](0);

        bytes memory hookData = _encodeV4HookData(users.creator, v3Route, v4Route, address(0), initialOrderSize, 0);

        // Deploy Content Coin paired with ETH (address(0))
        (address coinAddress, uint256 amountCurrency, uint256 coinsPurchased) = _deployContentCoinWithHook(
            address(0),
            initialOrderSize,
            users.creator,
            hookData
        );

        ContentCoin coin = ContentCoin(payable(coinAddress));

        // Verify the coin is properly configured as ETH-paired
        assertEq(coin.currency(), address(0), "Coin should be paired with ETH");
        assertEq(amountCurrency, initialOrderSize, "Should have used all ETH directly");
        assertGt(coinsPurchased, 0, "Should have purchased coins");

        // Creator should have their launch reward + purchased coins
        assertEq(
            coin.balanceOf(users.creator),
            CoinConstants.CONTENT_COIN_INITIAL_CREATOR_SUPPLY + coinsPurchased,
            "Creator should have launch reward + purchased coins"
        );
    }

    /// @dev Test deploying Content Coin with owned Creator Coin tokens (no ETH, no V3 swap)
    /// This demonstrates using existing ERC20 tokens to purchase initial supply during deployment
    function test_buyContentCoinSupply_WithOwnedCreatorCoins() public {
        // STEP 1: Deploy Creator Coin backed by ZORA
        address creatorCoinAddress = _deployCreatorCoin(users.creator);

        // STEP 2: Give another user ZORA tokens and have them swap for Creator Coins
        address anotherCreator = makeAddr("anotherCreator");
        uint256 zoraAmount = 10e18; // 10 ZORA tokens
        deal(ZORA, anotherCreator, zoraAmount);
        assertEq(IERC20(ZORA).balanceOf(anotherCreator), zoraAmount, "anotherCreator should have ZORA tokens");

        // Swap ZORA tokens for Creator Coins using proper V4 swap mechanism
        uint128 swapAmountIn = uint128(zoraAmount);
        _swapSomeCurrencyForCoin(ICoin(payable(creatorCoinAddress)), ZORA, swapAmountIn, anotherCreator);

        uint256 creatorCoinAmount = IERC20(creatorCoinAddress).balanceOf(anotherCreator);

        // STEP 3: Have anotherCreator approve the hook to spend their Creator Coins
        vm.prank(anotherCreator);
        IERC20(creatorCoinAddress).approve(address(postDeployHook), creatorCoinAmount);

        // STEP 4: Deploy Content Coin backed by Creator Coin using owned tokens

        // No V3 route needed - anotherCreator already has Creator Coins
        bytes memory v3Route = "";

        // No V4 route needed - direct Creator Coin to Content Coin swap
        PoolKey[] memory v4Route = new PoolKey[](0);

        bytes memory hookData = _encodeV4HookData(anotherCreator, v3Route, v4Route, creatorCoinAddress, creatorCoinAmount, 0);

        // Deploy with amount = 0 (no ETH needed since using owned tokens)
        (address contentCoinAddress, uint256 amountCurrency, uint256 coinsPurchased) = _deployContentCoinWithHook(
            creatorCoinAddress,
            0, // No ETH needed
            anotherCreator,
            hookData
        );

        ContentCoin contentCoin = ContentCoin(payable(contentCoinAddress));

        // Verify the content coin is properly configured
        assertEq(contentCoin.currency(), creatorCoinAddress, "Content coin should be backed by Creator coin");
        assertGt(amountCurrency, 0, "Should have used some Creator Coins");
        assertGt(coinsPurchased, 0, "Should have purchased content coins");

        // anotherCreator should have their launch reward + purchased content coins
        assertEq(
            contentCoin.balanceOf(anotherCreator),
            CoinConstants.CONTENT_COIN_INITIAL_CREATOR_SUPPLY + coinsPurchased,
            "anotherCreator should have launch reward + purchased content coins"
        );

        // Verify Creator Coin balance decreased
        uint256 remainingCreatorCoins = IERC20(creatorCoinAddress).balanceOf(anotherCreator);
        assertLt(remainingCreatorCoins, creatorCoinAmount, "anotherCreator should have spent some Creator Coins");
        assertEq(remainingCreatorCoins, creatorCoinAmount - amountCurrency, "Creator Coin balance should decrease by amount used");
    }

    /// @dev Test buying initial supply of a Content Coin backed by a Creator Coin
    /// This requires V3 swap (ETH -> ZORA) then V4 swap (ZORA -> Creator Coin -> Content Coin)
    function test_buyContentCoinSupply_CreatorCoinBacked() public {
        uint256 initialOrderSize = 0.08 ether;
        vm.deal(users.creator, initialOrderSize);

        // STEP 1: Deploy Creator Coin backed by ZORA
        address creatorCoinAddress = _deployCreatorCoin(users.creator);

        // STEP 2: Deploy Content Coin backed by Creator Coin

        // Create V3 path: ETH -> USDC -> ZORA (to get the creator coin's backing currency)
        bytes memory v3Route = _encodeV3Path(
            address(weth),
            3000, // WETH/USDC 0.3%
            USDC_ADDRESS,
            3000, // USDC/ZORA 0.3%
            ZORA
        );

        // V4 route: ZORA -> Creator Coin (then Creator Coin -> Content Coin will be added automatically)
        PoolKey[] memory v4Route = new PoolKey[](1);
        v4Route[0] = ICoin(payable(creatorCoinAddress)).getPoolKey();

        bytes memory hookData = _encodeV4HookData(users.creator, v3Route, v4Route, address(0), initialOrderSize, 0);

        (address contentCoinAddress, uint256 amountCurrency, uint256 coinsPurchased) = _deployContentCoinWithHook(
            creatorCoinAddress,
            initialOrderSize,
            users.creator,
            hookData
        );

        ContentCoin contentCoin = ContentCoin(payable(contentCoinAddress));

        // Verify the content coin is properly configured
        assertEq(contentCoin.currency(), creatorCoinAddress, "Content coin should be backed by Creator coin");
        assertGt(amountCurrency, 0, "Should have received ZORA from V3 swap");
        assertGt(coinsPurchased, 0, "Should have purchased content coins");

        // Creator should have their launch reward + purchased content coins
        assertEq(
            contentCoin.balanceOf(users.creator),
            CoinConstants.CONTENT_COIN_INITIAL_CREATOR_SUPPLY + coinsPurchased,
            "Creator should have launch reward + purchased content coins"
        );
    }

    // ============ ERROR HANDLING TESTS ============

    function test_RevertWhen_InsufficientInputCurrencyETH() public {
        uint256 inputAmount = 1 ether;
        uint256 insufficientAmount = 0.5 ether;

        // Create V3 path: ETH -> USDC -> ZORA
        bytes memory v3Route = _encodeV3Path(
            address(weth),
            3000, // WETH/USDC 0.3%
            USDC_ADDRESS,
            3000, // USDC/ZORA 0.3%
            ZORA
        );

        PoolKey[] memory v4Route = new PoolKey[](0);

        bytes memory hookData = _encodeV4HookData(users.creator, v3Route, v4Route, address(0), inputAmount, 0);

        // Should revert with InsufficientInputCurrency
        vm.deal(users.creator, insufficientAmount);
        bytes memory poolConfig = CoinConfigurationVersions.defaultDopplerMultiCurveUniV4(ZORA);
        vm.expectRevert(abi.encodeWithSelector(V3ToV4SwapLib.InsufficientInputCurrency.selector, inputAmount, insufficientAmount));

        vm.prank(users.creator);
        factory.deployWithHook{value: insufficientAmount}(
            users.creator, // payoutRecipient
            _getDefaultOwners(), // owners
            "https://test.com", // uri
            "Content Coin", // name
            "CONTENT", // symbol
            poolConfig, // poolConfig
            users.platformReferrer, // platformReferrer
            address(postDeployHook), // postDeployHook
            hookData // postDeployHookData
        );
    }

    function test_RevertWhen_InsufficientInputCurrencyERC20() public {
        // Deploy Creator Coin first
        address creatorCoinAddress = _deployCreatorCoin(users.creator);

        uint256 userBalance = 500e18;

        // Give user some Creator Coins but less than required
        deal(creatorCoinAddress, users.creator, userBalance);

        // Approve a small amount to spend for Creator Coins
        vm.prank(users.creator);
        IERC20(creatorCoinAddress).approve(address(postDeployHook), 1);

        // No V3 route needed - user already has Creator Coins (but insufficient amount)
        bytes memory v3Route = "";
        PoolKey[] memory v4Route = new PoolKey[](0);

        uint256 zoraAmount = 10e18; // 10 ZORA tokens
        deal(ZORA, users.creator, zoraAmount);

        // Swap ZORA tokens for Creator Coins using proper V4 swap mechanism
        uint128 swapAmountIn = uint128(zoraAmount);
        _swapSomeCurrencyForCoin(ICoin(payable(creatorCoinAddress)), ZORA, swapAmountIn, users.creator);

        uint256 inputAmount = IERC20(creatorCoinAddress).balanceOf(users.creator);
        uint256 amountToApprove = inputAmount / 2;

        // only approve half of the input amount - it should revert
        vm.prank(users.creator);
        IERC20(creatorCoinAddress).approve(address(postDeployHook), amountToApprove);

        bytes memory hookData = _encodeV4HookData(users.creator, v3Route, v4Route, creatorCoinAddress, inputAmount, 0);

        bytes memory poolConfig = CoinConfigurationVersions.defaultDopplerMultiCurveUniV4(creatorCoinAddress);
        // Should revert with InsufficientInputCurrency
        vm.expectRevert(abi.encodeWithSelector(V3ToV4SwapLib.InsufficientInputCurrency.selector, inputAmount, amountToApprove));

        vm.prank(users.creator);
        factory.deployWithHook(
            users.creator, // payoutRecipient
            _getDefaultOwners(), // owners
            "https://test.com", // uri
            "Content Coin", // name
            "CONTENT", // symbol
            poolConfig, // poolConfig
            users.platformReferrer, // platformReferrer
            address(postDeployHook), // postDeployHook
            hookData // postDeployHookData
        );
    }

    function test_RevertWhen_V3RouteDoesNotConnectToV4RouteStart() public {
        // Deploy Creator Coin backed by ZORA
        address creatorCoinAddress = _deployCreatorCoin(users.creator);

        vm.deal(users.creator, 1 ether);

        // Create V3 path that ends with USDC
        bytes memory v3Route = _encodeV3PathSingle(
            address(weth),
            3000, // WETH/USDC 0.3%
            USDC_ADDRESS
        );

        // Create V4 route that starts with ZORA (not USDC - mismatch!)
        PoolKey[] memory v4Route = new PoolKey[](1);
        v4Route[0] = ICoin(payable(creatorCoinAddress)).getPoolKey();

        bytes memory hookData = _encodeV4HookData(users.creator, v3Route, v4Route, address(0), 1 ether, 0);

        // Should revert with V3RouteDoesNotConnectToV4RouteStart

        bytes memory poolConfig = CoinConfigurationVersions.defaultDopplerMultiCurveUniV4(creatorCoinAddress);

        vm.prank(users.creator);
        vm.expectRevert(abi.encodeWithSelector(V3ToV4SwapLib.V3RouteDoesNotConnectToV4RouteStart.selector));
        factory.deployWithHook{value: 1 ether}(
            users.creator, // payoutRecipient
            _getDefaultOwners(), // owners
            "https://test.com", // uri
            "Content Coin", // name
            "CONTENT", // symbol
            poolConfig, // poolConfig
            users.platformReferrer, // platformReferrer
            address(postDeployHook), // postDeployHook
            hookData // postDeployHookData
        );
    }

    function test_RevertWhen_InsufficientOutputAmount() public {
        uint256 initialOrderSize = 0.1 ether;
        vm.deal(users.creator, initialOrderSize);

        // Create V3 path: ETH -> USDC -> ZORA
        bytes memory v3Route = _encodeV3Path(
            address(weth),
            3000, // WETH/USDC 0.3%
            USDC_ADDRESS,
            3000, // USDC/ZORA 0.3%
            ZORA
        );

        // No V4 route needed since coin is backed by ZORA
        PoolKey[] memory v4Route = new PoolKey[](0);

        // Set impossibly high minimum amount out (1 million coins)
        uint256 impossibleMinAmountOut = type(uint256).max;

        bytes memory hookData = _encodeV4HookData(users.creator, v3Route, v4Route, address(0), initialOrderSize, impossibleMinAmountOut);

        // Should revert with InsufficientOutputAmount
        bytes memory poolConfig = CoinConfigurationVersions.defaultDopplerMultiCurveUniV4(ZORA);
        vm.expectRevert(abi.encodeWithSelector(BuySupplyWithV4SwapHook.InsufficientOutputAmount.selector));

        vm.prank(users.creator);
        factory.deployWithHook{value: initialOrderSize}(
            users.creator, // payoutRecipient
            _getDefaultOwners(), // owners
            "https://test.com", // uri
            "Content Coin", // name
            "CONTENT", // symbol
            poolConfig, // poolConfig
            users.platformReferrer, // platformReferrer
            address(postDeployHook), // postDeployHook
            hookData // postDeployHookData
        );
    }
}
