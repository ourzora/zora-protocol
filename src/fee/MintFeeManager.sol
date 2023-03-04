// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {TransferHelperUtils} from "../utils/TransferHelperUtils.sol";
import {IMintFeeManager} from "../interfaces/IMintFeeManager.sol";

/// @title MintFeeManager
/// @notice Manages mint fees for an 1155 contract
contract MintFeeManager is IMintFeeManager {
    uint256 public immutable mintFee;
    address public immutable mintFeeRecipient;

    constructor(uint256 _mintFee, address _mintFeeRecipient) {
        // Set fixed finders fee
        if (_mintFee >= 0.1 ether) {
            revert MintFeeCannotBeMoreThanZeroPointOneETH(_mintFee);
        }
        if (_mintFeeRecipient == address(0) && _mintFee > 0) {
            revert CannotSetMintFeeToZeroAddress();
        }
        mintFeeRecipient = _mintFeeRecipient;
        mintFee = _mintFee;
    }

    /// @notice Sends teh mint fee to the mint fee recipient and returns the amount of ETH remaining that can be used in this transaction
    function _handleFeeAndGetValueSent() internal returns (uint256 ethValueSent) {
        ethValueSent = msg.value;

        // Handle mint fee
        if (mintFeeRecipient != address(0)) {
            ethValueSent -= mintFee;
            if (!TransferHelperUtils.safeSendETHLowLimit(mintFeeRecipient, mintFee)) {
                revert CannotSendMintFee(mintFeeRecipient, mintFee);
            }
        }
    }
}
