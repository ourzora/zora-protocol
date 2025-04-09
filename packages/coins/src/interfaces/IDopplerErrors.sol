// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IDopplerErrors {
    error NumDiscoveryPositionsOutOfRange();

    error CannotMintZeroLiquidity();

    /// @notice Thrown when the tick range is misordered
    error InvalidTickRangeMisordered(int24 tickLower, int24 tickUpper);

    /// @notice Thrown when the max share to be sold exceeds the maximum unit
    error MaxShareToBeSoldExceeded(uint256 value, uint256 limit);
}
