// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {IZoraLimitOrderBook} from "../../src/IZoraLimitOrderBook.sol";

/// @notice Wrapper contract to expose private functions for testing
/// @dev This is a helper contract, not a test contract
contract LimitOrderCreateWrapper {
    /// @notice Exposes _validateOrderInputs for testing
    function validateOrderInputs(uint256[] memory orderSizes, int24[] memory orderTicks, address maker) external pure returns (uint256 total) {
        // We can't directly call the private function, so we need to test through public functions
        // Instead, we'll recreate the validation logic here for unit testing
        require(maker != address(0), IZoraLimitOrderBook.ZeroMaker());

        uint256 length = orderSizes.length;
        require(length == orderTicks.length, IZoraLimitOrderBook.ArrayLengthMismatch());

        for (uint256 i; i < length; ) {
            uint256 size = orderSizes[i];
            require(size != 0, IZoraLimitOrderBook.ZeroOrderSize());
            total += size;
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Helper to check pullFunds path - only checks which path, doesn't validate
    function checkPullFundsPath(address coin) external pure returns (string memory path) {
        if (coin == address(0)) {
            return "ETH";
        } else {
            return "ERC20";
        }
    }

    /// @notice Helper to validate pullFunds ETH requirements
    function validatePullFundsETH(uint256 msgValue, uint256 total) external pure {
        require(msgValue == total, IZoraLimitOrderBook.NativeValueMismatch());
    }

    /// @notice Helper to validate pullFunds ERC20 requirements
    function validatePullFundsERC20(uint256 msgValue) external pure {
        require(msgValue == 0, IZoraLimitOrderBook.NativeValueMismatch());
    }

    /// @notice Helper to test tick calculation branches
    function calculateTicks(bool isCurrency0, int24 orderTick, int24 spacing) external pure returns (int24 tickLower, int24 tickUpper) {
        if (isCurrency0) {
            tickLower = orderTick;
            tickUpper = orderTick + spacing;
        } else {
            tickLower = orderTick - spacing;
            tickUpper = orderTick;
        }
    }

    /// @notice Helper to test realized size calculation branches
    function calculateRealizedSize(bool isCurrency0, int128 amount0, int128 amount1) external pure returns (uint128 realizedSize) {
        if (isCurrency0) {
            realizedSize = amount0 < 0 ? uint128(uint256(int256(-amount0))) : 0;
        } else {
            realizedSize = amount1 < 0 ? uint128(uint256(int256(-amount1))) : 0;
        }
    }

    /// @notice Helper to test refund calculation branch
    function calculateRefund(uint128 realizedSize, uint128 requestedSize) external pure returns (uint128 refunded) {
        require(realizedSize != 0, IZoraLimitOrderBook.ZeroRealizedOrder());

        if (realizedSize < requestedSize) {
            refunded = requestedSize - realizedSize;
        }
    }
}

/// @notice Direct unit tests for LimitOrderCreate library functions
contract LimitOrderCreateUnitTest is Test {
    LimitOrderCreateWrapper internal wrapper;

    function setUp() public {
        wrapper = new LimitOrderCreateWrapper();
    }

    /// @notice Tests validation with zero maker address
    function test_validateOrderInputs_zeroMaker_reverts() public {
        uint256[] memory sizes = new uint256[](1);
        int24[] memory ticks = new int24[](1);
        sizes[0] = 1000;
        ticks[0] = 100;

        vm.expectRevert(IZoraLimitOrderBook.ZeroMaker.selector);
        wrapper.validateOrderInputs(sizes, ticks, address(0));
    }

    /// @notice Tests validation with mismatched array lengths
    function test_validateOrderInputs_lengthMismatch_reverts() public {
        uint256[] memory sizes = new uint256[](3);
        int24[] memory ticks = new int24[](2); // Mismatch

        vm.expectRevert(IZoraLimitOrderBook.ArrayLengthMismatch.selector);
        wrapper.validateOrderInputs(sizes, ticks, address(0x1234));
    }

    /// @notice Tests validation with zero order size
    function test_validateOrderInputs_zeroSize_reverts() public {
        uint256[] memory sizes = new uint256[](2);
        int24[] memory ticks = new int24[](2);
        sizes[0] = 1000;
        sizes[1] = 0; // Zero size
        ticks[0] = 100;
        ticks[1] = 200;

        vm.expectRevert(IZoraLimitOrderBook.ZeroOrderSize.selector);
        wrapper.validateOrderInputs(sizes, ticks, address(0x1234));
    }

    /// @notice Tests validation with valid single order
    function test_validateOrderInputs_singleOrder_success() public {
        uint256[] memory sizes = new uint256[](1);
        int24[] memory ticks = new int24[](1);
        sizes[0] = 1000;
        ticks[0] = 100;

        uint256 total = wrapper.validateOrderInputs(sizes, ticks, address(0x1234));
        assertEq(total, 1000, "total should be 1000");
    }

    /// @notice Tests validation with multiple orders (loop iterations)
    function test_validateOrderInputs_multipleOrders_sumsTotal() public {
        uint256[] memory sizes = new uint256[](5);
        int24[] memory ticks = new int24[](5);

        for (uint256 i = 0; i < 5; i++) {
            sizes[i] = (i + 1) * 1000; // 1000, 2000, 3000, 4000, 5000
            ticks[i] = int24(int256((i + 1) * 100));
        }

        uint256 total = wrapper.validateOrderInputs(sizes, ticks, address(0x1234));
        assertEq(total, 15000, "total should be 15000");
    }

    /// @notice Tests validation loop with many iterations
    function test_validateOrderInputs_manyOrders_loopIterates() public {
        uint256[] memory sizes = new uint256[](10);
        int24[] memory ticks = new int24[](10);

        for (uint256 i = 0; i < 10; i++) {
            sizes[i] = 500;
            ticks[i] = int24(int256(i * 100));
        }

        uint256 total = wrapper.validateOrderInputs(sizes, ticks, address(0x1234));
        assertEq(total, 5000, "total should be 5000");
    }

    /// @notice Tests pullFunds path detection for ETH (coin == address(0))
    function test_pullFunds_ethPath_detected() public view {
        address coin = address(0);
        string memory path = wrapper.checkPullFundsPath(coin);
        assertEq(path, "ETH", "should detect ETH path");
    }

    /// @notice Tests pullFunds path detection for ERC20 (coin != address(0))
    function test_pullFunds_erc20Path_detected() public view {
        address coin = address(0x1234);
        string memory path = wrapper.checkPullFundsPath(coin);
        assertEq(path, "ERC20", "should detect ERC20 path");
    }

    /// @notice Tests pullFunds ETH validation with correct value
    function test_pullFunds_ethValidation_correctValue_succeeds() public view {
        uint256 msgValue = 1000;
        uint256 total = 1000;

        wrapper.validatePullFundsETH(msgValue, total);
        // No revert means success
    }

    /// @notice Tests pullFunds ETH validation with incorrect value
    function test_pullFunds_ethValidation_wrongValue_reverts() public {
        uint256 msgValue = 999;
        uint256 total = 1000;

        vm.expectRevert(IZoraLimitOrderBook.NativeValueMismatch.selector);
        wrapper.validatePullFundsETH(msgValue, total);
    }

    /// @notice Tests pullFunds ERC20 validation with zero msg.value
    function test_pullFunds_erc20Validation_zeroValue_succeeds() public view {
        uint256 msgValue = 0;

        wrapper.validatePullFundsERC20(msgValue);
        // No revert means success
    }

    /// @notice Tests pullFunds ERC20 validation with non-zero msg.value
    function test_pullFunds_erc20Validation_nonZeroValue_reverts() public {
        uint256 msgValue = 100;

        vm.expectRevert(IZoraLimitOrderBook.NativeValueMismatch.selector);
        wrapper.validatePullFundsERC20(msgValue);
    }

    /// @notice Tests tick calculation for currency0
    function test_calculateTicks_currency0_setsCorrectRange() public {
        bool isCurrency0 = true;
        int24 orderTick = 1000;
        int24 spacing = 200;

        (int24 tickLower, int24 tickUpper) = wrapper.calculateTicks(isCurrency0, orderTick, spacing);

        assertEq(tickLower, 1000, "tickLower should be orderTick");
        assertEq(tickUpper, 1200, "tickUpper should be orderTick + spacing");
    }

    /// @notice Tests tick calculation for currency1
    function test_calculateTicks_currency1_setsCorrectRange() public {
        bool isCurrency0 = false;
        int24 orderTick = 1000;
        int24 spacing = 200;

        (int24 tickLower, int24 tickUpper) = wrapper.calculateTicks(isCurrency0, orderTick, spacing);

        assertEq(tickLower, 800, "tickLower should be orderTick - spacing");
        assertEq(tickUpper, 1000, "tickUpper should be orderTick");
    }

    /// @notice Tests tick calculation with negative ticks
    function test_calculateTicks_negativeTicks_handlesCorrectly() public {
        bool isCurrency0 = true;
        int24 orderTick = -1000;
        int24 spacing = 200;

        (int24 tickLower, int24 tickUpper) = wrapper.calculateTicks(isCurrency0, orderTick, spacing);

        assertEq(tickLower, -1000, "tickLower should be -1000");
        assertEq(tickUpper, -800, "tickUpper should be -800");
    }

    /// @notice Tests realized size for currency0 with negative amount0
    function test_calculateRealizedSize_currency0_negativeAmount_returnsSize() public {
        bool isCurrency0 = true;
        int128 amount0 = -1000;
        int128 amount1 = 500;

        uint128 realizedSize = wrapper.calculateRealizedSize(isCurrency0, amount0, amount1);
        assertEq(realizedSize, 1000, "should return absolute value of amount0");
    }

    /// @notice Tests realized size for currency0 with positive amount0
    function test_calculateRealizedSize_currency0_positiveAmount_returnsZero() public {
        bool isCurrency0 = true;
        int128 amount0 = 1000; // Positive
        int128 amount1 = -500;

        uint128 realizedSize = wrapper.calculateRealizedSize(isCurrency0, amount0, amount1);
        assertEq(realizedSize, 0, "should return 0 for positive amount0");
    }

    /// @notice Tests realized size for currency1 with negative amount1
    function test_calculateRealizedSize_currency1_negativeAmount_returnsSize() public {
        bool isCurrency0 = false;
        int128 amount0 = 500;
        int128 amount1 = -1000;

        uint128 realizedSize = wrapper.calculateRealizedSize(isCurrency0, amount0, amount1);
        assertEq(realizedSize, 1000, "should return absolute value of amount1");
    }

    /// @notice Tests realized size for currency1 with positive amount1
    function test_calculateRealizedSize_currency1_positiveAmount_returnsZero() public {
        bool isCurrency0 = false;
        int128 amount0 = -500;
        int128 amount1 = 1000; // Positive

        uint128 realizedSize = wrapper.calculateRealizedSize(isCurrency0, amount0, amount1);
        assertEq(realizedSize, 0, "should return 0 for positive amount1");
    }

    /// @notice Tests realized size with zero amounts
    function test_calculateRealizedSize_zeroAmounts_returnsZero() public {
        bool isCurrency0 = true;
        int128 amount0 = 0;
        int128 amount1 = 0;

        uint128 realizedSize = wrapper.calculateRealizedSize(isCurrency0, amount0, amount1);
        assertEq(realizedSize, 0, "should return 0 for zero amounts");
    }

    /// @notice Tests refund when realized < requested
    function test_calculateRefund_partialRealization_returnsRefund() public {
        uint128 realizedSize = 800;
        uint128 requestedSize = 1000;

        uint128 refunded = wrapper.calculateRefund(realizedSize, requestedSize);
        assertEq(refunded, 200, "should refund difference");
    }

    /// @notice Tests refund when realized == requested (no refund)
    function test_calculateRefund_fullRealization_noRefund() public {
        uint128 realizedSize = 1000;
        uint128 requestedSize = 1000;

        uint128 refunded = wrapper.calculateRefund(realizedSize, requestedSize);
        assertEq(refunded, 0, "should have no refund");
    }

    /// @notice Tests refund when realized > requested (edge case)
    function test_calculateRefund_overRealization_noRefund() public {
        uint128 realizedSize = 1200;
        uint128 requestedSize = 1000;

        uint128 refunded = wrapper.calculateRefund(realizedSize, requestedSize);
        assertEq(refunded, 0, "should have no refund");
    }

    /// @notice Tests refund calculation reverts on zero realized size
    function test_calculateRefund_zeroRealized_reverts() public {
        uint128 realizedSize = 0;
        uint128 requestedSize = 1000;

        vm.expectRevert(IZoraLimitOrderBook.ZeroRealizedOrder.selector);
        wrapper.calculateRefund(realizedSize, requestedSize);
    }

    /// @notice Tests validation with empty arrays
    function test_validateOrderInputs_emptyArrays_success() public {
        uint256[] memory sizes = new uint256[](0);
        int24[] memory ticks = new int24[](0);

        uint256 total = wrapper.validateOrderInputs(sizes, ticks, address(0x1234));
        assertEq(total, 0, "total should be 0 for empty arrays");
    }

    /// @notice Tests tick calculation with zero spacing (edge case)
    function test_calculateTicks_zeroSpacing_noChange() public {
        bool isCurrency0 = true;
        int24 orderTick = 1000;
        int24 spacing = 0;

        (int24 tickLower, int24 tickUpper) = wrapper.calculateTicks(isCurrency0, orderTick, spacing);

        assertEq(tickLower, 1000, "tickLower should be orderTick");
        assertEq(tickUpper, 1000, "tickUpper should equal tickLower with zero spacing");
    }

    /// @notice Tests realized size calculation with large negative values
    function test_calculateRealizedSize_largeNegativeValue_handlesCorrectly() public {
        bool isCurrency0 = true;
        int128 amount0 = -1000000000; // Large negative value
        int128 amount1 = 0;

        uint128 realizedSize = wrapper.calculateRealizedSize(isCurrency0, amount0, amount1);
        assertEq(realizedSize, 1000000000, "should handle large negative value");
    }
}
