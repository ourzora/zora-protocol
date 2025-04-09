// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {CoinConfigurationVersions} from "../src/libs/CoinConfigurationVersions.sol";
import {MarketConstants} from "../src/libs/MarketConstants.sol";
import {BaseTest} from "./utils/BaseTest.sol";
import {Coin} from "../src/Coin.sol";
import {IUniswapV3Pool} from "../src/interfaces/IUniswapV3Pool.sol";
import {LpPosition} from "../src/types/LpPosition.sol";
import {IDopplerErrors} from "../src/interfaces/IDopplerErrors.sol";
import {CoinDopplerUniV3} from "../src/libs/CoinDopplerUniV3.sol";
import {TickMath} from "../src/utils/uniswap/TickMath.sol";

contract DopplerUniswapV3Test is BaseTest {
    int24 internal constant DEFAULT_DISCOVERY_TICK_LOWER = -777000;
    int24 internal constant DEFAULT_DISCOVERY_TICK_UPPER = 222000;
    uint16 internal constant DEFAULT_NUM_DISCOVERY_POSITIONS = 10; // will be 11 total with tail position
    uint256 internal constant DEFAULT_DISCOVERY_SUPPLY_SHARE = 0.495e18; // half of the 990m total pool supply

    function _generatePoolConfig(
        uint8 version_,
        address currency_,
        int24 tickLower_,
        int24 tickUpper_,
        uint16 numDiscoveryPositions_,
        uint256 maxDiscoverySupplyShare_
    ) internal pure returns (bytes memory) {
        return abi.encode(version_, currency_, tickLower_, tickUpper_, numDiscoveryPositions_, maxDiscoverySupplyShare_);
    }

    function _deployCoin(bytes memory poolConfig_) internal {
        vm.prank(users.creator);
        (address coinAddress, ) = factory.deploy(
            users.creator,
            _getDefaultOwners(),
            "https://test.com",
            "Testcoin",
            "TEST",
            poolConfig_,
            users.platformReferrer,
            0
        );

        coin = Coin(payable(coinAddress));
        pool = IUniswapV3Pool(coin.poolAddress());

        vm.label(address(coin), "COIN");
        vm.label(address(pool), "POOL");
    }

    function setUp() public override {
        super.setUp();
    }

    function test_deploy_legacy_eth_config() public {
        bytes memory poolConfig = _generatePoolConfig(
            CoinConfigurationVersions.LEGACY_POOL_VERSION,
            address(weth),
            MarketConstants.LP_TICK_LOWER_WETH,
            0,
            1,
            0
        );

        _deployCoin(poolConfig);

        assertEq(coin.currency(), address(weth), "currency");
        assertEq(coin.totalSupply(), 1_000_000_000e18, "totalSupply");
        assertEq(coin.balanceOf(users.creator), 10_000_000e18, "balanceOf creator");
        assertGt(coin.balanceOf(coin.poolAddress()), 989_999_999e18, "balanceOf pool");

        (
            address asset,
            address numeraire,
            int24 tickLower,
            int24 tickUpper,
            uint16 numPositions,
            bool isInitialized,
            bool isExited,
            uint256 maxShareToBeSold,
            uint256 totalTokensOnBondingCurve
        ) = coin.poolState();

        assertEq(asset, address(coin));
        assertEq(numeraire, address(weth));
        assertEq(numPositions, 1);
        assertTrue(isInitialized);
        assertFalse(isExited);
        assertEq(maxShareToBeSold, 0);
        assertEq(totalTokensOnBondingCurve, POOL_LAUNCH_SUPPLY);

        bool isCoinToken0 = address(coin) < address(weth);

        if (isCoinToken0) {
            assertEq(tickLower, MarketConstants.LP_TICK_LOWER_WETH);
            assertEq(tickUpper, MarketConstants.LP_TICK_UPPER);
        } else {
            assertEq(tickLower, -MarketConstants.LP_TICK_UPPER);
            assertEq(tickUpper, -MarketConstants.LP_TICK_LOWER_WETH);
        }
    }

    function test_invalid_tick_range() public {
        bytes memory poolConfig = _generatePoolConfig(CoinConfigurationVersions.LEGACY_POOL_VERSION, address(weth), -100, 100, 100, 0.5e18);

        vm.expectRevert();
        factory.deploy(users.creator, _getDefaultOwners(), "https://test.com", "Testcoin", "TEST", poolConfig, users.platformReferrer, 0);
    }

    function test_inverted_tick_range_revert() public {
        // These tick ranges are flipped
        bytes memory poolConfig = _generatePoolConfig(CoinConfigurationVersions.LEGACY_POOL_VERSION, address(weth), 10000, -10000, 100, 0.5e18);

        vm.expectRevert(abi.encodeWithSignature("InvalidWethLowerTick()"));
        factory.deploy(users.creator, _getDefaultOwners(), "https://test.com", "Testcoin", "TEST", poolConfig, users.platformReferrer, 0);
    }

    function test_deploy_legacy_eth_config_with_prebuy(uint256 initialOrderSize) public {
        vm.assume(initialOrderSize > MIN_ORDER_SIZE);
        vm.assume(initialOrderSize < 10 ether);

        vm.deal(users.creator, initialOrderSize);

        bytes memory poolConfig = _generatePoolConfig(
            CoinConfigurationVersions.LEGACY_POOL_VERSION,
            address(weth),
            MarketConstants.LP_TICK_LOWER_WETH,
            0,
            0,
            0
        );

        vm.prank(users.creator);
        (address coinAddress, ) = factory.deploy{value: initialOrderSize}(
            users.creator,
            _getDefaultOwners(),
            "https://test.com",
            "Testcoin",
            "TEST",
            poolConfig,
            users.platformReferrer,
            initialOrderSize
        );

        coin = Coin(payable(coinAddress));
        pool = IUniswapV3Pool(coin.poolAddress());

        assertGt(coin.balanceOf(users.creator), 10_000_000e18, "balanceOf creator");
    }

    function test_deploy_legacy_usdc_config_with_prebuy() public {
        address[] memory owners = new address[](1);
        owners[0] = users.creator;

        uint256 orderSize = dealUSDC(users.creator, 100);

        vm.prank(users.creator);
        usdc.approve(address(factory), orderSize);

        bytes memory poolConfig = _generatePoolConfig(CoinConfigurationVersions.LEGACY_POOL_VERSION, address(usdc), USDC_TICK_LOWER, 0, 0, 0);

        vm.prank(users.creator);
        (address coinAddress, uint256 coinsPurchased) = factory.deploy(
            users.creator,
            owners,
            "https://testcoinusdcpair.com",
            "Testcoinusdcpair",
            "TESTCOINUSDCPAIR",
            poolConfig,
            users.platformReferrer,
            orderSize
        );
        coin = Coin(payable(coinAddress));
        pool = IUniswapV3Pool(coin.poolAddress());
        vm.label(address(coin), "COIN");
        vm.label(address(pool), "POOL");

        assertEq(coin.currency(), address(usdc), "currency");
        assertEq(coin.balanceOf(users.creator), CREATOR_LAUNCH_REWARD + coinsPurchased);
    }

    function test_deploy_doppler_eth() public {
        bytes memory poolConfig = _generatePoolConfig(
            CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION,
            address(weth),
            DEFAULT_DISCOVERY_TICK_LOWER,
            DEFAULT_DISCOVERY_TICK_UPPER,
            DEFAULT_NUM_DISCOVERY_POSITIONS,
            DEFAULT_DISCOVERY_SUPPLY_SHARE
        );

        _deployCoin(poolConfig);

        (
            address asset,
            address numeraire,
            ,
            ,
            uint16 numPositions,
            bool isInitialized,
            bool isExited,
            uint256 maxShareToBeSold,
            uint256 totalTokensOnBondingCurve
        ) = coin.poolState();

        assertEq(asset, address(coin), "poolState.asset");
        assertEq(numeraire, address(weth), "poolState.numeraire");
        assertEq(numPositions, DEFAULT_NUM_DISCOVERY_POSITIONS, "poolState.numPositions");
        assertTrue(isInitialized, "poolState.isInitialized");
        assertFalse(isExited, "poolState.isExited");
        assertEq(maxShareToBeSold, DEFAULT_DISCOVERY_SUPPLY_SHARE, "poolState.maxShareToBeSold");
        assertEq(totalTokensOnBondingCurve, POOL_LAUNCH_SUPPLY, "poolState.totalTokensOnBondingCurve");
    }

    function test_deploy_doppler_eth_with_prebuy(uint256 initialOrderSize) public {
        vm.assume(initialOrderSize > MIN_ORDER_SIZE);
        vm.assume(initialOrderSize < 1 ether);

        vm.deal(users.creator, initialOrderSize);

        bytes memory poolConfig = _generatePoolConfig(
            CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION,
            address(weth),
            DEFAULT_DISCOVERY_TICK_LOWER,
            DEFAULT_DISCOVERY_TICK_UPPER,
            DEFAULT_NUM_DISCOVERY_POSITIONS,
            DEFAULT_DISCOVERY_SUPPLY_SHARE
        );

        vm.prank(users.creator);
        (address coinAddress, uint256 coinsPurchased) = factory.deploy{value: initialOrderSize}(
            users.creator,
            _getDefaultOwners(),
            "https://test.com",
            "Testcoin",
            "TEST",
            poolConfig,
            users.platformReferrer,
            initialOrderSize
        );

        coin = Coin(payable(coinAddress));
        pool = IUniswapV3Pool(coin.poolAddress());

        assertEq(coin.currency(), address(weth), "currency");
        assertGt(coinsPurchased, 0, "coinsPurchased > 0");
        assertEq(coin.balanceOf(users.creator), CREATOR_LAUNCH_REWARD + coinsPurchased, "balanceOf creator");
        assertGt(weth.balanceOf(address(pool)), 0, "Pool WETH balance");
    }

    function test_invalid_pool_config() public {
        bytes memory poolConfig = _generatePoolConfig(CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION, address(weth), -100, 100, 0, 10);

        vm.expectRevert(abi.encodeWithSignature("NumDiscoveryPositionsOutOfRange()"));
        factory.deploy(users.creator, _getDefaultOwners(), "https://test.com", "Testcoin", "TEST", poolConfig, users.platformReferrer, 0);
    }

    function test_revert_deploy_invalid_discovery_supply_share() public {
        bytes memory poolConfig = _generatePoolConfig(
            CoinConfigurationVersions.DOPPLER_UNI_V3_POOL_VERSION,
            address(weth),
            DEFAULT_DISCOVERY_TICK_LOWER,
            DEFAULT_DISCOVERY_TICK_UPPER,
            DEFAULT_NUM_DISCOVERY_POSITIONS,
            1.1e18
        );

        vm.expectRevert(abi.encodeWithSelector(IDopplerErrors.MaxShareToBeSoldExceeded.selector, 1.1e18, 1e18));
        factory.deploy(users.creator, _getDefaultOwners(), "https://test.com", "Testcoin", "TEST", poolConfig, users.platformReferrer, 0);
    }

    function test_alignTick_isToken0_positive() public pure {
        int24 tick = 12345;
        int24 TICK_SPACING = 60;
        int24 expected = 12300;

        assertEq(CoinDopplerUniV3.alignTickToTickSpacing(true, tick, TICK_SPACING), expected, "Align positive tick (token0)");
    }

    function test_alignTick_isToken0_negative() public pure {
        int24 tick = -12345;
        int24 TICK_SPACING = 60;
        int24 expected = -12360;
        assertEq(CoinDopplerUniV3.alignTickToTickSpacing(true, tick, TICK_SPACING), expected, "Align negative tick (token0)");
    }

    function test_alignTick_isToken1_negative() public pure {
        int24 tick = -12345;
        int24 TICK_SPACING = 60;
        int24 expected = -12300;
        assertEq(CoinDopplerUniV3.alignTickToTickSpacing(false, tick, TICK_SPACING), expected, "Align negative tick (token1)");
    }

    function test_alignTick_isToken1_zero() public pure {
        int24 tick = 0;
        int24 expected = 0;
        assertEq(CoinDopplerUniV3.alignTickToTickSpacing(false, tick, MarketConstants.TICK_SPACING), expected, "Align zero tick (token1)");
    }

    // Additional tick alignment test for full branch coverage
    function test_alignTick_isToken0_zero() public pure {
        int24 tick = 0;
        int24 expected = 0;
        assertEq(CoinDopplerUniV3.alignTickToTickSpacing(true, tick, MarketConstants.TICK_SPACING), expected, "Align zero tick (token0)");
    }

    function test_alignTick_isToken1_positive() public pure {
        int24 tick = 12345;
        int24 expected = 12400; // Round up for token1
        assertEq(CoinDopplerUniV3.alignTickToTickSpacing(false, tick, MarketConstants.TICK_SPACING), expected, "Align positive tick (token1)");
    }

    function test_calculateLpTail_isToken0() public pure {
        int24 tickLower = DEFAULT_DISCOVERY_TICK_LOWER;
        int24 tickUpper = DEFAULT_DISCOVERY_TICK_UPPER;
        uint256 tailSupply = 1e18;
        bool isToken0 = true;

        LpPosition memory tail = CoinDopplerUniV3.calculateLpTail(tickLower, tickUpper, isToken0, tailSupply, MarketConstants.TICK_SPACING);

        int24 expectedPosTickLower = tickUpper;
        int24 expectedPosTickUpper = CoinDopplerUniV3.alignTickToTickSpacing(true, TickMath.MAX_TICK, MarketConstants.TICK_SPACING);

        assertEq(tail.tickLower, expectedPosTickLower, "Tail tickLower (token0)");
        assertEq(tail.tickUpper, expectedPosTickUpper, "Tail tickUpper (token0)");
        assertGt(tail.liquidity, 0, "Tail liquidity should be > 0 (token0)");
    }

    function test_calculateLpTail_isToken1() public pure {
        int24 tickLower = DEFAULT_DISCOVERY_TICK_LOWER;
        int24 tickUpper = DEFAULT_DISCOVERY_TICK_UPPER;
        uint256 tailSupply = 1e18;
        bool isToken0 = false;

        LpPosition memory tail = CoinDopplerUniV3.calculateLpTail(tickLower, tickUpper, isToken0, tailSupply, MarketConstants.TICK_SPACING);

        int24 expectedPosTickLower = CoinDopplerUniV3.alignTickToTickSpacing(false, TickMath.MIN_TICK, MarketConstants.TICK_SPACING);
        int24 expectedPosTickUpper = tickLower;

        assertEq(tail.tickLower, expectedPosTickLower, "Tail tickLower (token1)");
        assertEq(tail.tickUpper, expectedPosTickUpper, "Tail tickUpper (token1)");
        assertGt(tail.liquidity, 0, "Tail liquidity should be > 0 (token1)");
    }

    function test_calculateLogNormalDistribution_isToken0() public pure {
        int24 tickLower = -60000;
        int24 tickUpper = 0;
        bool isToken0 = true;
        uint256 discoverySupply = 100e18;
        LpPosition[] memory newPositions = new LpPosition[](DEFAULT_NUM_DISCOVERY_POSITIONS);

        (LpPosition[] memory positions, uint256 totalAssetsSold) = CoinDopplerUniV3.calculateLogNormalDistribution(
            tickLower,
            tickUpper,
            MarketConstants.TICK_SPACING,
            isToken0,
            discoverySupply,
            DEFAULT_NUM_DISCOVERY_POSITIONS,
            newPositions
        );

        assertEq(positions.length, DEFAULT_NUM_DISCOVERY_POSITIONS, "Correct number of positions (token0)");
        assertTrue(totalAssetsSold <= discoverySupply, "Total assets sold <= discovery supply (token0)");
        assertTrue(totalAssetsSold > 0, "Total assets sold > 0 (token0)");

        int24 expectedFarTick = tickUpper; // 0
        for (uint i = 0; i < DEFAULT_NUM_DISCOVERY_POSITIONS; i++) {
            assertTrue(positions[i].liquidity > 0, "Position liquidity > 0 (token0)");
            assertTrue(positions[i].tickLower <= positions[i].tickUpper, "Tick order check (token0)");
            assertEq(positions[i].tickLower % MarketConstants.TICK_SPACING, 0, "Lower tick alignment (token0)");
            assertEq(positions[i].tickUpper % MarketConstants.TICK_SPACING, 0, "Upper tick alignment (token0)");
            assertEq(positions[i].tickUpper, expectedFarTick, "Far tick check (token0)");
        }
    }

    function test_calculateLogNormalDistribution_isToken1() public pure {
        int24 tickLower = -60000;
        int24 tickUpper = 0;
        bool isToken0 = false;
        uint256 discoverySupply = 100e18;
        LpPosition[] memory newPositions = new LpPosition[](DEFAULT_NUM_DISCOVERY_POSITIONS);

        (LpPosition[] memory positions, uint256 totalAssetsSold) = CoinDopplerUniV3.calculateLogNormalDistribution(
            tickLower,
            tickUpper,
            MarketConstants.TICK_SPACING,
            isToken0,
            discoverySupply,
            DEFAULT_NUM_DISCOVERY_POSITIONS,
            newPositions
        );

        assertEq(positions.length, DEFAULT_NUM_DISCOVERY_POSITIONS, "Correct number of positions (token1)");
        assertTrue(totalAssetsSold <= discoverySupply, "Total assets sold <= discovery supply (token1)");
        assertTrue(totalAssetsSold > 0, "Total assets sold > 0 (token1)");

        int24 expectedFarTick = tickLower; // -60000
        for (uint i = 0; i < DEFAULT_NUM_DISCOVERY_POSITIONS; i++) {
            assertTrue(positions[i].liquidity > 0, "Position liquidity > 0 (token1)");
            assertTrue(positions[i].tickLower <= positions[i].tickUpper, "Tick order check (token1)");
            assertEq(positions[i].tickLower % MarketConstants.TICK_SPACING, 0, "Lower tick alignment (token1)");
            assertEq(positions[i].tickUpper % MarketConstants.TICK_SPACING, 0, "Upper tick alignment (token1)");
            assertEq(positions[i].tickLower, expectedFarTick, "Far tick check (token1)");
        }
    }

    function test_calculateLogNormalDistribution_zeroDiscoverySupply() public pure {
        int24 tickLower = -60000;
        int24 tickUpper = 0;
        bool isToken0 = true;
        uint256 discoverySupply = 0;
        LpPosition[] memory newPositions = new LpPosition[](DEFAULT_NUM_DISCOVERY_POSITIONS);

        (LpPosition[] memory positions, uint256 totalAssetsSold) = CoinDopplerUniV3.calculateLogNormalDistribution(
            tickLower,
            tickUpper,
            MarketConstants.TICK_SPACING,
            isToken0,
            discoverySupply,
            DEFAULT_NUM_DISCOVERY_POSITIONS,
            newPositions
        );

        assertEq(positions.length, DEFAULT_NUM_DISCOVERY_POSITIONS, "Correct number of positions (zero supply)");
        assertEq(totalAssetsSold, 0, "Total assets sold is 0 (zero supply)");

        for (uint i = 0; i < DEFAULT_NUM_DISCOVERY_POSITIONS; i++) {
            assertEq(positions[i].liquidity, 0, "Position liquidity is 0 (zero supply)");
            assertTrue(positions[i].tickLower <= positions[i].tickUpper, "Tick order check (zero supply)");
            assertEq(positions[i].tickLower % MarketConstants.TICK_SPACING, 0, "Lower tick alignment (zero supply)");
            assertEq(positions[i].tickUpper % MarketConstants.TICK_SPACING, 0, "Upper tick alignment (zero supply)");
        }
    }

    function test_calculateLogNormalDistribution_startingTickEqualsFarTick() public pure {
        // Will force startingTick == farTick
        int24 tickLower = 0;
        int24 tickUpper = 0;

        bool isToken0 = true;
        uint256 discoverySupply = 100e18;
        uint16 totalPositions = 1;
        LpPosition[] memory newPositions = new LpPosition[](totalPositions);

        (LpPosition[] memory positions, uint256 totalAssetsSold) = CoinDopplerUniV3.calculateLogNormalDistribution(
            tickLower,
            tickUpper,
            MarketConstants.TICK_SPACING,
            isToken0,
            discoverySupply,
            totalPositions,
            newPositions
        );

        assertEq(positions.length, totalPositions, "Correct number of positions");
        assertEq(totalAssetsSold, 0, "No assets sold when startingTick equals farTick");
        assertEq(positions[0].liquidity, 0, "Position should have zero liquidity");
    }
}
