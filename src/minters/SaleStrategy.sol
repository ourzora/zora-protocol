// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {IVersionedContract} from "../interfaces/IVersionedContract.sol";

abstract contract SaleStrategy is IMinter1155, IVersionedContract {
    function contractURI() external virtual returns (string memory);

    function contractName() external virtual returns (string memory);

    function contractVersion() external virtual returns (string memory);

    function resetSale(uint256 tokenId) external virtual;

    event SaleRemoved(address targetContract, uint256 tokenId);

    function _getKey(address mediaContract, uint256 tokenId) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(mediaContract, tokenId)));
    }
}
