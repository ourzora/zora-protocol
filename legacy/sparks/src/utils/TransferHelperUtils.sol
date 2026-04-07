// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IZoraSparks1155} from "../interfaces/IZoraSparks1155.sol";
import {IZoraSparks1155Errors} from "../interfaces/IZoraSparks1155.sol";

/// @title TransferHelperUtils
/// @notice Helper functions for sending ETH
library TransferHelperUtils {
    // @dev Gas limit to send funds
    uint256 internal constant FUNDS_SEND_LARGE_GAS_LIMIT = 1_675_000;

    /// @notice Sends ETH to a recipient, making conservative estimates to not run out of gas
    /// @param recipient The address to send ETH to
    /// @param value The amount of ETH to send
    function safeSendETH(address recipient, uint256 value) internal {
        (bool success, ) = recipient.call{value: value, gas: FUNDS_SEND_LARGE_GAS_LIMIT}("");
        if (!success) {
            revert IZoraSparks1155Errors.ETHTransferFailed();
        }
    }
}
