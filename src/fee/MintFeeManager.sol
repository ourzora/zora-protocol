// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {TransferHelperUtils} from "../utils/TransferHelperUtils.sol";
import {IMintFeeManager} from "../interfaces/IMintFeeManager.sol";

contract MintFeeManager is IMintFeeManager {
    uint256 public immutable mintFeeBPS;

    constructor(uint256 _mintFeeBPS) {
        // Set fixed finders fee
        if (_mintFeeBPS >= 10_000) {
            revert FindersFeeCannotBe100OrMore(_mintFeeBPS);
        }
        mintFeeBPS = _mintFeeBPS;
    }

    function _handleFeeAndGetValueSent(address mintFeeRecipient)
        internal
        returns (uint256 ethValueSent)
    {
        ethValueSent = msg.value;
        // Handle mint fee
        if (mintFeeRecipient != address(0)) {
            uint256 mintFee = ethValueSent * (mintFeeBPS / 10_000);
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
