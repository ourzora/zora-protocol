// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC165Upgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC165Upgradeable.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {IContractMetadata} from "../interfaces/IContractMetadata.sol";
import {IVersionedContract} from "@zoralabs/shared-contracts/interfaces/IVersionedContract.sol";

/// @notice Sales Strategy Helper contract template on top of IMinter1155
/// @author @iainnash / @tbtstl
abstract contract SaleStrategy is IMinter1155, IVersionedContract, IContractMetadata {
    /// @notice This function resets the sales configuration for a given tokenId and contract.
    /// @dev This function is intentioned to be called directly from the affected sales contract
    function resetSale(uint256 tokenId) external virtual;

    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return interfaceId == type(IMinter1155).interfaceId || interfaceId == type(IERC165Upgradeable).interfaceId;
    }
}
