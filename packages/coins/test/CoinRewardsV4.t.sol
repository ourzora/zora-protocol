// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {CoinRewardsV4} from "../src/libs/CoinRewardsV4.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";

contract CoinRewardsV4Harness {
    function getTradeReferral(bytes calldata hookData) external pure returns (address) {
        return CoinRewardsV4.getTradeReferral(hookData);
    }
}

contract CoinRewardsV4Test is Test {
    CoinRewardsV4Harness internal harness;
    address internal constant TRADE_REFERRER = 0x1234567890123456789012345678901234567890;

    function setUp() public {
        harness = new CoinRewardsV4Harness();
    }

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

    function test_getTradeReferral_returnsZeroAddress_forHookDataUnderTwentyBytes(uint8 length) public view {
        vm.assume(length < 20);

        assertEq(harness.getTradeReferral(_bytesOfLength(length)), address(0));
    }

    function test_getTradeReferral_returnsZeroAddress_forTwentyByteHookData() public view {
        assertEq(harness.getTradeReferral(_bytesOfLength(20)), address(0));
    }

    function test_getTradeReferral_returnsZeroAddress_forTwentyOneThroughThirtyOneByteHookData(uint8 length) public view {
        length = uint8(bound(length, 21, 31));

        assertEq(harness.getTradeReferral(_bytesOfLength(length)), address(0));
    }

    function test_getTradeReferral_decodesAbiEncodedAddress() public view {
        assertEq(harness.getTradeReferral(abi.encode(TRADE_REFERRER)), TRADE_REFERRER);
    }

    function test_getTradeReferral_decodesAbiEncodedAddressWithTrailingData() public view {
        bytes memory hookData = abi.encodePacked(abi.encode(TRADE_REFERRER), bytes12(uint96(0xabcdef)));

        assertGt(hookData.length, 32);
        assertEq(harness.getTradeReferral(hookData), TRADE_REFERRER);
    }

    function _bytesOfLength(uint256 length) private pure returns (bytes memory data) {
        data = new bytes(length);

        for (uint256 i; i < length; i++) {
            data[i] = bytes1(uint8(i + 1));
        }
    }
}
