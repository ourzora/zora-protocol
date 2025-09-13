// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./utils/BaseTest.sol";

import {ICreatorCoin} from "../src/interfaces/ICreatorCoin.sol";
import {ICreatorCoinHook} from "../src/interfaces/ICreatorCoinHook.sol";
import {CreatorCoinConstants} from "../src/libs/CreatorCoinConstants.sol";
import {CoinRewardsV4} from "../src/libs/CoinRewardsV4.sol";
import {UniV4SwapHelper} from "../src/libs/UniV4SwapHelper.sol";

contract CreatorCoinTest is BaseTest {
    CreatorCoin internal creatorCoin;

    function setUp() public override {
        super.setUpWithBlockNumber(30267794);

        deal(address(zoraToken), address(poolManager), 1_000_000_000e18);

        _deployCreatorCoin();
    }

    function _getMultiCurvePoolConfig() internal view returns (bytes memory) {
        int24[] memory tickLower = new int24[](1);
        int24[] memory tickUpper = new int24[](1);
        uint16[] memory numDiscoveryPositions = new uint16[](1);
        uint256[] memory maxDiscoverySupplyShare = new uint256[](1);

        tickLower[0] = -138_000;
        tickUpper[0] = 81_000;
        numDiscoveryPositions[0] = 11;
        maxDiscoverySupplyShare[0] = 0.05e18;

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

    function _deployCreatorCoin() internal {
        bytes memory poolConfig = _getMultiCurvePoolConfig();

        vm.prank(users.creator);
        address creatorCoinAddress = factory.deployCreatorCoin(
            users.creator,
            _getDefaultOwners(),
            "https://test.com",
            "Testcoin",
            "TEST",
            poolConfig,
            address(0),
            bytes32(0)
        );

        creatorCoin = CreatorCoin(creatorCoinAddress);
        vm.label(address(creatorCoin), "TEST_CREATOR_COIN");
    }

    function test_deploy_creator_coin() public view {
        assertEq(creatorCoin.name(), "Testcoin");
        assertEq(creatorCoin.symbol(), "TEST");
        assertEq(creatorCoin.payoutRecipient(), users.creator);
        assertEq(creatorCoin.currency(), CreatorCoinConstants.CURRENCY);
        assertEq(creatorCoin.totalSupply(), CreatorCoinConstants.TOTAL_SUPPLY);

        assertEq(creatorCoin.balanceOf(address(creatorCoin)), CreatorCoinConstants.CREATOR_VESTING_SUPPLY);
        assertEq(creatorCoin.balanceOf(address(creatorCoin.poolManager())), MarketConstants.CREATOR_COIN_MARKET_SUPPLY);
    }

    function test_deploy_creator_coin_with_invalid_currency_reverts() public {
        int24[] memory tickLower = new int24[](1);
        int24[] memory tickUpper = new int24[](1);
        uint16[] memory numDiscoveryPositions = new uint16[](1);
        uint256[] memory maxDiscoverySupplyShare = new uint256[](1);

        tickLower[0] = -138_000;
        tickUpper[0] = 81_000;
        numDiscoveryPositions[0] = 11;
        maxDiscoverySupplyShare[0] = 0.05e18;

        bytes memory poolConfig = abi.encode(
            CoinConfigurationVersions.DOPPLER_MULTICURVE_UNI_V4_POOL_VERSION,
            address(weth), // Invalid currency
            tickLower,
            tickUpper,
            numDiscoveryPositions,
            maxDiscoverySupplyShare
        );

        vm.prank(users.creator);
        vm.expectRevert(ICreatorCoin.InvalidCurrency.selector);
        factory.deployCreatorCoin(users.creator, _getDefaultOwners(), "https://test.com", "Testcoin", "TEST", poolConfig, address(0), bytes32(0));
    }

    // function test_deploy_creator_coin_with_content_coin_succeeds() public {
    //     _deployV4Coin(address(creatorCoin));
    // }

    function test_vesting_initialization() public view {
        uint256 deploymentTime = block.timestamp;

        assertEq(creatorCoin.vestingStartTime(), deploymentTime);
        assertEq(creatorCoin.vestingEndTime(), deploymentTime + CreatorCoinConstants.CREATOR_VESTING_DURATION);
        assertEq(creatorCoin.totalClaimed(), 0);
    }

    function test_getClaimableAmount_at_launch() public view {
        assertEq(creatorCoin.getClaimableAmount(), 0);
    }

    function test_getClaimableAmount_before_vesting_starts() public {
        // Even if we go back in time (hypothetically), nothing should be claimable
        vm.warp(creatorCoin.vestingStartTime() - 1);
        assertEq(creatorCoin.getClaimableAmount(), 0);
    }

    function test_getClaimableAmount_after_one_year() public {
        uint256 oneYear = 365 days;
        vm.warp(creatorCoin.vestingStartTime() + oneYear);

        // After 1 year out of 5, should be able to claim 20% of vesting supply
        uint256 expectedClaimable = (CreatorCoinConstants.CREATOR_VESTING_SUPPLY * oneYear) / CreatorCoinConstants.CREATOR_VESTING_DURATION;
        assertEq(creatorCoin.getClaimableAmount(), expectedClaimable);
    }

    function test_getClaimableAmount_after_half_vesting_period() public {
        uint256 halfVesting = CreatorCoinConstants.CREATOR_VESTING_DURATION / 2;
        vm.warp(creatorCoin.vestingStartTime() + halfVesting);

        // After 2.5 years, should be able to claim 50% of vesting supply
        uint256 expectedClaimable = CreatorCoinConstants.CREATOR_VESTING_SUPPLY / 2;
        assertEq(creatorCoin.getClaimableAmount(), expectedClaimable);
    }

    function test_getClaimableAmount_after_full_vesting_period() public {
        vm.warp(creatorCoin.vestingEndTime());

        // After full vesting period, should be able to claim entire vesting supply
        assertEq(creatorCoin.getClaimableAmount(), CreatorCoinConstants.CREATOR_VESTING_SUPPLY);
    }

    function test_getClaimableAmount_after_vesting_period_ends() public {
        vm.warp(creatorCoin.vestingEndTime() + 365 days);

        // Even after vesting ends, should still be able to claim entire vesting supply
        assertEq(creatorCoin.getClaimableAmount(), CreatorCoinConstants.CREATOR_VESTING_SUPPLY);
    }

    function test_getClaimableAmount_after_one_day() public {
        // Test with a specific timestamp to verify precision
        uint256 oneDay = 1 days;
        vm.warp(creatorCoin.vestingStartTime() + oneDay);

        uint256 expectedClaimable = (CreatorCoinConstants.CREATOR_VESTING_SUPPLY * oneDay) / CreatorCoinConstants.CREATOR_VESTING_DURATION;
        assertEq(creatorCoin.getClaimableAmount(), expectedClaimable);

        // Verify it's a small but non-zero amount
        assertGt(expectedClaimable, 0);
        assertLt(expectedClaimable, CreatorCoinConstants.CREATOR_VESTING_SUPPLY / 1000); // Less than 0.1%
    }

    function test_claimVesting_at_launch() public {
        uint256 claimedAmount = creatorCoin.claimVesting();
        assertEq(claimedAmount, 0);
        assertEq(creatorCoin.totalClaimed(), 0);
        assertEq(creatorCoin.balanceOf(users.creator), 0);
    }

    function test_claimVesting_after_one_year() public {
        uint256 oneYear = 365 days;
        vm.warp(creatorCoin.vestingStartTime() + oneYear);

        uint256 expectedClaimable = (CreatorCoinConstants.CREATOR_VESTING_SUPPLY * oneYear) / CreatorCoinConstants.CREATOR_VESTING_DURATION;
        uint256 initialCreatorBalance = creatorCoin.balanceOf(users.creator);
        uint256 initialContractBalance = creatorCoin.balanceOf(address(creatorCoin));

        vm.expectEmit(true, false, false, true);
        emit ICreatorCoin.CreatorVestingClaimed(
            users.creator,
            expectedClaimable,
            expectedClaimable,
            creatorCoin.vestingStartTime(),
            creatorCoin.vestingEndTime()
        );

        uint256 claimedAmount = creatorCoin.claimVesting();

        assertEq(claimedAmount, expectedClaimable);
        assertEq(creatorCoin.totalClaimed(), expectedClaimable);
        assertEq(creatorCoin.balanceOf(users.creator), initialCreatorBalance + expectedClaimable);
        assertEq(creatorCoin.balanceOf(address(creatorCoin)), initialContractBalance - expectedClaimable);
    }

    function test_claimVesting_multiple_claims() public {
        uint256 oneYear = 365 days;

        // First claim after 1 year
        vm.warp(creatorCoin.vestingStartTime() + oneYear);
        uint256 expectedClaim1 = (CreatorCoinConstants.CREATOR_VESTING_SUPPLY * oneYear) / CreatorCoinConstants.CREATOR_VESTING_DURATION;
        uint256 claimed1 = creatorCoin.claimVesting();

        assertEq(claimed1, expectedClaim1);
        assertEq(creatorCoin.totalClaimed(), expectedClaim1);
        assertEq(creatorCoin.balanceOf(users.creator), expectedClaim1);

        // Second claim after another year (2 years total)
        vm.warp(creatorCoin.vestingStartTime() + 2 * oneYear);
        uint256 totalVestedAfter2Years = (CreatorCoinConstants.CREATOR_VESTING_SUPPLY * 2 * oneYear) / CreatorCoinConstants.CREATOR_VESTING_DURATION;
        uint256 expectedClaim2 = totalVestedAfter2Years - expectedClaim1;

        uint256 claimed2 = creatorCoin.claimVesting();

        assertEq(claimed2, expectedClaim2);
        assertEq(creatorCoin.totalClaimed(), totalVestedAfter2Years);
        assertEq(creatorCoin.balanceOf(users.creator), totalVestedAfter2Years);
    }

    function test_claimVesting_no_double_claiming() public {
        uint256 oneYear = 365 days;
        vm.warp(creatorCoin.vestingStartTime() + oneYear);

        // First claim
        uint256 claimed1 = creatorCoin.claimVesting();
        assertGt(claimed1, 0);

        // Immediate second claim should return 0
        uint256 claimed2 = creatorCoin.claimVesting();
        assertEq(claimed2, 0);

        // Total claimed should remain the same
        assertEq(creatorCoin.totalClaimed(), claimed1);
    }

    function test_claimVesting_after_full_vesting() public {
        vm.warp(creatorCoin.vestingEndTime());

        uint256 claimedAmount = creatorCoin.claimVesting();

        assertEq(claimedAmount, CreatorCoinConstants.CREATOR_VESTING_SUPPLY);
        assertEq(creatorCoin.totalClaimed(), CreatorCoinConstants.CREATOR_VESTING_SUPPLY);
        assertEq(creatorCoin.balanceOf(users.creator), CreatorCoinConstants.CREATOR_VESTING_SUPPLY);

        // Subsequent claims should return 0
        uint256 secondClaim = creatorCoin.claimVesting();
        assertEq(secondClaim, 0);
    }

    function test_claimVesting_partial_then_full() public {
        uint256 halfVesting = CreatorCoinConstants.CREATOR_VESTING_DURATION / 2;

        // Claim half way through vesting
        vm.warp(creatorCoin.vestingStartTime() + halfVesting);
        uint256 partialClaim = creatorCoin.claimVesting();
        assertEq(partialClaim, CreatorCoinConstants.CREATOR_VESTING_SUPPLY / 2);

        // Claim the rest after full vesting
        vm.warp(creatorCoin.vestingEndTime());
        uint256 remainingClaim = creatorCoin.claimVesting();
        assertEq(remainingClaim, CreatorCoinConstants.CREATOR_VESTING_SUPPLY / 2);

        // Total should equal full vesting supply
        assertEq(creatorCoin.totalClaimed(), CreatorCoinConstants.CREATOR_VESTING_SUPPLY);
        assertEq(creatorCoin.balanceOf(users.creator), CreatorCoinConstants.CREATOR_VESTING_SUPPLY);
    }

    function test_vesting_calculation_edge_cases() public {
        // Test at exact vesting start time
        vm.warp(creatorCoin.vestingStartTime());
        assertEq(creatorCoin.getClaimableAmount(), 0);

        // Test one second after vesting starts
        vm.warp(creatorCoin.vestingStartTime() + 1);
        uint256 claimableAfterOneSecond = creatorCoin.getClaimableAmount();
        assertGt(claimableAfterOneSecond, 0);
        assertLt(claimableAfterOneSecond, CreatorCoinConstants.CREATOR_VESTING_SUPPLY / 1000000); // Very small amount

        // Test one second before vesting ends
        vm.warp(creatorCoin.vestingEndTime() - 1);
        uint256 claimableBeforeEnd = creatorCoin.getClaimableAmount();
        assertLt(claimableBeforeEnd, CreatorCoinConstants.CREATOR_VESTING_SUPPLY);
        assertGt(claimableBeforeEnd, CreatorCoinConstants.CREATOR_VESTING_SUPPLY - (CreatorCoinConstants.CREATOR_VESTING_SUPPLY / 1000000));

        // Test at exact vesting end time
        vm.warp(creatorCoin.vestingEndTime());
        assertEq(creatorCoin.getClaimableAmount(), CreatorCoinConstants.CREATOR_VESTING_SUPPLY);
    }

    function test_vesting_frequent_small_claims() public {
        uint256 startTime = creatorCoin.vestingStartTime();
        uint256 totalClaimed = 0;

        // Make small claims every day for a week
        for (uint256 i = 1; i <= 7; i++) {
            vm.warp(startTime + i * 1 days);
            uint256 claimed = creatorCoin.claimVesting();
            totalClaimed += claimed;
        }

        // Verify total claimed matches expected amount for 7 days
        uint256 expectedTotal = (CreatorCoinConstants.CREATOR_VESTING_SUPPLY * 7 days) / CreatorCoinConstants.CREATOR_VESTING_DURATION;
        assertEq(totalClaimed, expectedTotal);
        assertEq(creatorCoin.totalClaimed(), expectedTotal);
    }

    function test_buy(uint128 amountIn) public {
        vm.assume(amountIn > 0.00001e18);
        vm.assume(amountIn < 500_000e18);

        deal(address(zoraToken), users.buyer, amountIn);
        assertEq(zoraToken.balanceOf(users.buyer), amountIn);

        vm.warp(block.timestamp + 1 days);

        vm.startPrank(users.buyer);
        UniV4SwapHelper.approveTokenWithPermit2(permit2, address(router), address(zoraToken), uint128(amountIn), uint48(block.timestamp + 1 days));

        (bytes memory commands, bytes[] memory inputs) = UniV4SwapHelper.buildExactInputSingleSwapCommand(
            address(zoraToken),
            uint128(amountIn),
            address(creatorCoin),
            0,
            creatorCoin.getPoolKey(),
            bytes("")
        );

        router.execute(commands, inputs, block.timestamp + 1 days);

        vm.stopPrank();

        uint256 buyerCCBalance = creatorCoin.balanceOf(users.buyer);
        assertGt(buyerCCBalance, 0, "buyer should have received creator coins");

        address payoutRecipient = creatorCoin.payoutRecipient();
        // payout recipient should not have coins balance, until they claim
        assertEq(creatorCoin.balanceOf(payoutRecipient), 0);

        creatorCoin.claimVesting();

        assertGt(creatorCoin.balanceOf(payoutRecipient), 0);
    }
}
