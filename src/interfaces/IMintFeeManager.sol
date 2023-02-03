// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IMintFeeManager {
    error FindersFeeCannotBe100OrMore(uint256 findersMintFeeBPS);

    error CannotSendMintFee(address mintFeeRecipient, uint256 mintFee);
}
