// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {TransferHelperUtils} from "../utils/TransferHelperUtils.sol";
import {IMintFeeManager} from "../interfaces/IMintFeeManager.sol";

contract MintFeeManager is IMintFeeManager {
    uint256 public immutable mintFee;

    constructor(uint256 _mintFee) {
        // Set fixed finders fee
        if (_mintFee >= 1 ether) {
            revert MintFeeCannotBeMoreThanOneETH(_mintFee);
        }
        mintFee = _mintFee;
    }

    function _handleFeeAndGetValueSent(address mintFeeRecipient)
        internal
        returns (uint256 ethValueSent)
    {
        ethValueSent = msg.value;
        // Handle mint fee
        if (mintFeeRecipient != address(0)) {
            ethValueSent -= mintFee;
            if (
                !TransferHelperUtils.safeSendETHLowLimit(
                    mintFeeRecipient,
                    mintFee
                )
            ) {
                revert CannotSendMintFee({
                    mintFeeRecipient: mintFeeRecipient,
                    mintFee: mintFee
                });
            }
        }
    }
}
