// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC165Upgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC165Upgradeable.sol";

interface ILimitedMintPerAddress is IERC165Upgradeable {
    error UserExceedsMintLimit(address user, uint256 limit, uint256 requestedAmount);

    function getMintedPerWallet(address token, uint256 tokenId, address wallet) external view returns (uint256);
}
