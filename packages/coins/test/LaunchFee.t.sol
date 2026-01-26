// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseTest} from "./utils/BaseTest.sol";
import {console} from "forge-std/console.sol";

import {CoinConstants} from "../src/libs/CoinConstants.sol";
import {IHasCreationInfo} from "../src/interfaces/IHasCreationInfo.sol";
import {UniV4SwapHelper} from "../src/libs/UniV4SwapHelper.sol";
import {ContentCoin} from "../src/ContentCoin.sol";
import {ICoin} from "../src/interfaces/ICoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

/// @notice Tests for the launch fee feature (time-based dynamic fee)
/// @dev IMPORTANT: This test uses forge-config pragma to run in isolation mode, which properly
///      simulates transaction boundaries for transient storage testing.
contract LaunchFeeTest is BaseTest {
    MockERC20 internal mockCurrency;
    ContentCoin internal coin;

    function setUp() public override {
        super.setUpNonForked();

        mockCurrency = new MockERC20("MockCurrency", "MCK");

        // Fund the pool manager with backing currency
        mockCurrency.mint(address(poolManager), 1_000_000_000 ether);
    }

    // ============================================
    // Interface Support Tests
    // ============================================

    function test_coinSupportsIHasCreationInfo() public {
        _deployCoin();

        bool supported = IERC165(address(coin)).supportsInterface(type(IHasCreationInfo).interfaceId);
        assertTrue(supported, "coin should support IHasCreationInfo");
    }

    /// forge-config: default.isolate = true
    function test_creationInfo_returnsCorrectValues() public {
        uint256 deployTime = block.timestamp;
        _deployCoin();

        (uint256 creationTimestamp, bool isDeploying) = IHasCreationInfo(address(coin)).creationInfo();

        assertEq(creationTimestamp, deployTime, "creation timestamp should match deploy time");
        assertFalse(isDeploying, "isDeploying should be false after deployment transaction");
    }

    // ============================================
    // Pool Key Tests
    // ============================================

    function test_poolKey_usesDynamicFeeFlag() public {
        _deployCoin();

        PoolKey memory poolKey = coin.getPoolKey();

        assertEq(poolKey.fee, CoinConstants.DYNAMIC_FEE_FLAG, "pool fee should use DYNAMIC_FEE_FLAG");
    }

    // ============================================
    // Launch Fee Calculation Tests
    // ============================================

    /// forge-config: default.isolate = true
    function test_launchFee_immediatelyAfterCreation() public {
        _deployCoin();

        uint128 amountIn = 1 ether;
        address trader = makeAddr("trader");

        // Snapshot to compare swaps from same starting state
        uint256 snapshot = vm.snapshotState();

        // Swap immediately (same block, but different transaction)
        // The launch fee should be at maximum (99%)
        mockCurrency.mint(trader, amountIn);
        uint256 coinBalanceBefore = coin.balanceOf(trader);
        _swapCurrencyForCoin(amountIn, trader);
        uint256 coinsAtMaxFee = coin.balanceOf(trader) - coinBalanceBefore;

        console.log("Coins received at t=0 (99% fee):", coinsAtMaxFee);

        // Revert to same starting state
        vm.revertToState(snapshot);

        // Warp past launch fee duration and do another swap from same starting state
        vm.warp(block.timestamp + CoinConstants.LAUNCH_FEE_DURATION + 1);

        mockCurrency.mint(trader, amountIn);
        coinBalanceBefore = coin.balanceOf(trader);
        _swapCurrencyForCoin(amountIn, trader);
        uint256 coinsAtMinFee = coin.balanceOf(trader) - coinBalanceBefore;

        console.log("Coins received at t>10s (1% fee):", coinsAtMinFee);

        // Coins received with 1% fee should be significantly more than with 99% fee
        assertGt(coinsAtMinFee, coinsAtMaxFee, "should receive more coins after launch fee ends");
    }

    /// forge-config: default.isolate = true
    function test_launchFee_decaysOverTime() public {
        _deployCoin();

        uint128 amountIn = 0.1 ether;
        address trader = makeAddr("trader");

        // Test at different time points
        uint256[] memory timePoints = new uint256[](5);
        timePoints[0] = 0; // 99% fee
        timePoints[1] = 2; // ~79.2% fee
        timePoints[2] = 5; // ~50% fee
        timePoints[3] = 8; // ~20.8% fee
        timePoints[4] = 10; // 1% fee

        uint256[] memory coinsReceived = new uint256[](5);

        for (uint256 i = 0; i < timePoints.length; i++) {
            // Reset state for each test
            uint256 snapshot = vm.snapshotState();

            if (timePoints[i] > 0) {
                vm.warp(block.timestamp + timePoints[i]);
            }

            mockCurrency.mint(trader, amountIn);
            uint256 coinBalanceBefore = coin.balanceOf(trader);

            _swapCurrencyForCoin(amountIn, trader);

            coinsReceived[i] = coin.balanceOf(trader) - coinBalanceBefore;

            console.log("Time:", timePoints[i], "s - Coins received:", coinsReceived[i]);

            vm.revertToState(snapshot);
        }

        // Verify monotonic increase (more coins as fee decreases)
        for (uint256 i = 1; i < coinsReceived.length; i++) {
            assertGt(coinsReceived[i], coinsReceived[i - 1], "coins received should increase as launch fee decays");
        }
    }

    /// forge-config: default.isolate = true
    function test_launchFee_exactlyAtDuration() public {
        _deployCoin();

        uint128 amountIn = 0.1 ether;
        address trader = makeAddr("trader");

        // Test at exactly the launch fee duration
        uint256 snapshot = vm.snapshotState();
        vm.warp(block.timestamp + CoinConstants.LAUNCH_FEE_DURATION);

        mockCurrency.mint(trader, amountIn);
        uint256 coinBalanceBefore = coin.balanceOf(trader);
        _swapCurrencyForCoin(amountIn, trader);
        uint256 coinsAtExactDuration = coin.balanceOf(trader) - coinBalanceBefore;

        vm.revertToState(snapshot);

        // Test after the launch fee duration (same starting state)
        vm.warp(block.timestamp + CoinConstants.LAUNCH_FEE_DURATION + 100);

        mockCurrency.mint(trader, amountIn);
        coinBalanceBefore = coin.balanceOf(trader);
        _swapCurrencyForCoin(amountIn, trader);
        uint256 coinsAfterDuration = coin.balanceOf(trader) - coinBalanceBefore;

        // Should be approximately equal (both at 1% fee, same pool state)
        assertApproxEqRel(coinsAtExactDuration, coinsAfterDuration, 0.01e18, "fee should be same at and after duration");
    }

    function test_launchFee_afterDurationEnds() public {
        _deployCoin();

        // Warp well past the launch fee duration
        vm.warp(block.timestamp + CoinConstants.LAUNCH_FEE_DURATION + 1 days);

        uint128 amountIn = 0.1 ether;
        address trader = makeAddr("trader");
        mockCurrency.mint(trader, amountIn);

        // Should use normal 1% LP fee
        _swapCurrencyForCoin(amountIn, trader);

        // Just verify the swap succeeded - fee calculation is 1%
        assertGt(coin.balanceOf(trader), 0, "trader should have received coins");
    }

    // ============================================
    // Initial Supply Bypass Tests
    // ============================================

    function test_initialSupply_bypassesLaunchFee() public {
        // The initial supply purchase during deployment should bypass launch fee
        // This is verified by checking the creator receives coins during deployment

        uint256 creatorBalanceBefore = 0; // Creator has no coins before deployment

        _deployCoin();

        uint256 creatorBalanceAfter = coin.balanceOf(users.creator);

        // Creator should receive initial supply (10 million for content coins)
        assertEq(creatorBalanceAfter, CoinConstants.CONTENT_COIN_INITIAL_CREATOR_SUPPLY, "creator should receive full initial supply without launch fee");
    }

    // ============================================
    // Fee Calculation Math Tests
    // ============================================

    function test_feeCalculation_linearDecay() public pure {
        // Test the fee calculation formula
        // fee = startFee - (elapsed / duration) * (startFee - endFee)

        uint256 startFee = CoinConstants.LAUNCH_FEE_START; // 990,000 (99%)
        uint256 endFee = CoinConstants.LP_FEE_V4; // 10,000 (1%)
        uint256 duration = CoinConstants.LAUNCH_FEE_DURATION; // 10 seconds

        // At t=0: fee should be 990,000
        uint256 feeAt0 = startFee - (0 * (startFee - endFee)) / duration;
        assertEq(feeAt0, 990_000, "fee at t=0");

        // At t=5: fee should be 500,000 (50%)
        uint256 feeAt5 = startFee - (5 * (startFee - endFee)) / duration;
        assertEq(feeAt5, 500_000, "fee at t=5");

        // At t=10: fee should be 10,000 (1%)
        uint256 feeAt10 = startFee - (10 * (startFee - endFee)) / duration;
        assertEq(feeAt10, 10_000, "fee at t=10");
    }

    // ============================================
    // Helper Functions
    // ============================================

    function _deployCoin() internal {
        bytes32 salt = keccak256(abi.encodePacked("launchFeeTest", block.timestamp));
        bytes memory poolConfig = _defaultPoolConfig(address(mockCurrency));

        vm.prank(users.creator);
        (address coinAddress, ) = factory.deploy(
            users.creator,
            _getDefaultOwners(),
            "https://test.com",
            "LaunchFeeCoin",
            "LAUNCH",
            poolConfig,
            address(0), // no platform referrer
            address(0), // no post deploy hook
            bytes(""),
            salt
        );

        coin = ContentCoin(payable(coinAddress));
        vm.label(address(coin), "LAUNCH_FEE_COIN");
    }

    function _swapCurrencyForCoin(uint128 amountIn, address trader) internal {
        uint128 minAmountOut = 0;

        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            address(mockCurrency),
            amountIn,
            address(coin),
            minAmountOut,
            coin.getPoolKey(),
            bytes("")
        );

        vm.startPrank(trader);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), address(mockCurrency), amountIn, uint48(block.timestamp + 1 days));

        router.execute(commands, inputs, block.timestamp + 1 days);
        vm.stopPrank();
    }
}
