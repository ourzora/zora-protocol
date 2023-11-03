// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC165Upgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC165Upgradeable.sol";

interface ILimitedMintPerAddressErrors {
    error UserExceedsMintLimit(address user, uint256 limit, uint256 requestedAmount);
}

interface ILimitedMintPerAddress is IERC165Upgradeable, ILimitedMintPerAddressErrors {
    function getMintedPerWallet(address token, uint256 tokenId, address wallet) external view returns (uint256);
}
