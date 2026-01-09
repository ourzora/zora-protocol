// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {SafeCast160} from "permit2/src/libraries/SafeCast160.sol";

/// @title Payments through Permit2
/// @notice Performs interactions with Permit2 to transfer tokens
/// @dev Based on Uniswap's universal-router Permit2Payments module
abstract contract Permit2Payments {
    using SafeCast160 for uint256;

    /// @notice The Permit2 contract address (immutable, same on all chains)
    IAllowanceTransfer internal immutable PERMIT2;

    error FromAddressIsNotOwner();

    constructor(address permit2_) {
        PERMIT2 = IAllowanceTransfer(permit2_);
    }

    /// @notice Performs a transferFrom on Permit2
    /// @param token The token to transfer
    /// @param from The address to transfer from
    /// @param to The recipient of the transfer
    /// @param amount The amount to transfer
    function permit2TransferFrom(address token, address from, address to, uint160 amount) internal {
        PERMIT2.transferFrom(from, to, amount, token);
    }

    /// @notice Performs a batch transferFrom on Permit2
    /// @param batchDetails An array detailing each of the transfers that should occur
    /// @param owner The address that should be the owner of all transfers
    function permit2TransferFrom(IAllowanceTransfer.AllowanceTransferDetails[] calldata batchDetails, address owner) internal {
        uint256 batchLength = batchDetails.length;
        for (uint256 i = 0; i < batchLength; ++i) {
            if (batchDetails[i].from != owner) revert FromAddressIsNotOwner();
        }
        PERMIT2.transferFrom(batchDetails);
    }
}
