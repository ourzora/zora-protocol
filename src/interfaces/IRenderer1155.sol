// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

interface IRenderer1155 is IERC165 {
    function uriFromContract(address sender, uint256 tokenId) external view returns (string memory);

    function setup(bytes memory initData) external;

    // IERC165 type required
}
