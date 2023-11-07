// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

contract ERC1155DelegationStorageV1 {
    struct ERC1155DelegationStorageV1Data {
        mapping(uint32 => uint256) delegatedTokenId;
    }

    function _get1155DelegationStorageV1() internal view returns (ERC1155DelegationStorageV1Data storage $) {
        assembly {
            $.slot := 510
        }
    }

    function delegatedTokenId(uint32 key) public view returns (uint256) {
        _get1155DelegationStorageV1().delegatedTokenId;
    }

}
