// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {IVersionedContract} from "../interfaces/IVersionedContract.sol";
import {ICreatorCommands} from "../interfaces/ICreatorCommands.sol";
import {SaleCommandHelper} from "./SaleCommandHelper.sol";

/// @notice Sales Strategy Helper contract template on top of IMinter1155
abstract contract SaleStrategy is IMinter1155, IVersionedContract {
    /// @notice Contract URI returns the uri for more information about the given contract
    function contractURI() external virtual returns (string memory);

    /// @notice Contract name returns the pretty contract name
    function contractName() external virtual returns (string memory);

    /// @notice Contract name returns the semver contract version
    function contractVersion() external virtual returns (string memory);

    /// @notice This function resets the sales configuration for a given tokenId and contract.
    /// @dev This function is intentioned to be called directly from the affected sales contract
    function resetSale(uint256 tokenId) external virtual;
}
