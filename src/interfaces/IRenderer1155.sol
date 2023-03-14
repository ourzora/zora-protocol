// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

interface IRenderer1155 is IERC165 {
    function uriFromContract(address sender, uint256 tokenId) external view returns (string memory);

    function setup(bytes memory initData) external;

    function uri(uint256 tokenId) external view returns (string memory);
    function contractURI() external view returns (string memory);

    // this is used to automatically set token transfer extension settings
    function shouldHaveTokenTransfer() external view returns (bool);

    /// @notice Token transfer batch
    /// @param target target contract for transfer
    /// @param operator operator address for transfer
    /// @param operator user address for amount transferred
    /// @param tokenIds list of token ids transferred
    /// @param values list of values transferred 
    function onTokenTransferBatch(address target, address operator, address user, uint256[] memory tokenIds, uint256[] memory values) external;

    // IERC165 type required
}
