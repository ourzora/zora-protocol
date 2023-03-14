// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IRenderer1155} from "../interfaces/IRenderer1155.sol";
import {IVersionedContract} from "../interfaces/IVersionedContract.sol";

abstract contract SaleStrategy is IVersionedContract {
    function contractURI() external virtual returns (string memory);

    function contractName() external virtual returns (string memory);

    function contractVersion() external virtual returns (string memory);

    function resetSale(uint256 tokenId) external virtual;

    function _getKey(address mediaContract, uint256 tokenId) internal pure returns (bytes32) {
        return keccak256(abi.encode(mediaContract, tokenId));
    }
}
