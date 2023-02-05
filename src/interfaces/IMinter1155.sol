// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IMinter1155 {
    function requestMint(
        address sender,
        uint256 tokenId,
        uint256 quantity,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external;
}
