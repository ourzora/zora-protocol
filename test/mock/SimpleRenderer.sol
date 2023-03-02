// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

import {IRenderer1155} from "../../src/interfaces/IRenderer1155.sol";

contract SimpleRenderer is IRenderer1155 {
    string internal uri;

    function uriFromContract(address, uint256) external view override returns (string memory) {
        return uri;
    }

    function setup(bytes memory data) external override {
        if (data.length == 0) {
            revert();
        }
        uri = string(data);
    }

    function supportsInterface(bytes4 interfaceID) external view returns (bool) {
        return interfaceID == type(IRenderer1155).interfaceId;
    }
}
