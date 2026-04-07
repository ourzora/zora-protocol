// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {TokenConfig} from "../ZoraSparksTypes.sol";

interface IZoraSparksAdmin {
    function createToken(uint256 tokenId, TokenConfig calldata tokenConfig) external;
}
