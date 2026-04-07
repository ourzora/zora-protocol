// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {CoinRewardsV4} from "../src/libs/CoinRewardsV4.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";

contract CoinRewardsV4Test is Test {
    function test_convertDeltaToPositiveUint128_success_with_valid_positive_values() public pure {
        // Test with small positive value
        int256 smallDelta = 1000;
        uint128 result = CoinRewardsV4.convertDeltaToPositiveUint128(smallDelta);
        assertEq(result, uint128(uint256(smallDelta)));

        // Test with large but valid positive value (within uint128 range)
        int256 largeDelta = int256(uint256(type(uint128).max));
        uint128 result2 = CoinRewardsV4.convertDeltaToPositiveUint128(largeDelta);
        assertEq(result2, type(uint128).max);

        // Test with zero
        int256 zeroDelta = 0;
        uint128 result3 = CoinRewardsV4.convertDeltaToPositiveUint128(zeroDelta);
        assertEq(result3, 0);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_convertDeltaToPositiveUint128_edge_cases_and_reverts(int8 difference) public {
        if (difference < 0) {
            vm.expectRevert(SafeCast.SafeCastOverflow.selector);
        }
        CoinRewardsV4.convertDeltaToPositiveUint128(difference);
    }
}
