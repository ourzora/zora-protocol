// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

contract ERC1155RewardsStorageV1 {
    mapping(uint256 => address) public createReferrals;

    mapping(uint256 => address) public firstMinters;
}
