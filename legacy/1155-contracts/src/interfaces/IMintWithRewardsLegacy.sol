// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IMinter1155} from "./IMinter1155.sol";

interface IMintWithRewardsLegacy {
    function mintWithRewards(IMinter1155 minter, uint256 tokenId, uint256 quantity, bytes calldata minterArguments, address mintReferral) external payable;
}
