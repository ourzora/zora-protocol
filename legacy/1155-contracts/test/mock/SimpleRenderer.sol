// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

import {IRenderer1155} from "../../src/interfaces/IRenderer1155.sol";

contract SimpleRenderer is IRenderer1155 {
    string internal _uri;
    string internal _contractURI;

    function uri(uint256) external view returns (string memory) {
        return _uri;
    }

    function contractURI() external view returns (string memory) {
        return _contractURI;
    }

    function setup(bytes memory data) external override {
        if (data.length == 0) {
            revert();
        }
        _uri = string(data);
    }

    function setContractURI(string memory _newURI) external {
        _contractURI = _newURI;
    }

    function supportsInterface(bytes4 interfaceID) external pure returns (bool) {
        return interfaceID == type(IRenderer1155).interfaceId;
    }
}
