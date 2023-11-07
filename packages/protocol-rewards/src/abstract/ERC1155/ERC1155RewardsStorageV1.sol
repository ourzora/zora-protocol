// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

contract ERC1155RewardsStorageV1 {
    struct ERC1155RewardsStorageV1Data {
        mapping(uint256 => address) createReferrals;

        mapping(uint256 => address) firstMinters;
    }

    function createReferrals(uint256 tokenId) public view returns (address) {
        return _get1155RewardsStorageV1().createReferrals[tokenId];
    }

    function firstMinters(uint256 tokenId) public view returns (address) {
        return _get1155RewardsStorageV1().firstMinters[tokenId];
    }

    function _get1155RewardsStorageV1() internal pure returns (ERC1155RewardsStorageV1Data storage $) {
        assembly {
            $.slot := 508
        }
    }

}
