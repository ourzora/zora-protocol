// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {IZoraCreator1155} from "./MockIZoraCreator1155.sol";

contract Mock1155NoCreatorRewardRecipient is ERC1155, IZoraCreator1155 {
    /// @notice This user role allows for any action to be performed
    uint256 public constant PERMISSION_BIT_ADMIN = 2 ** 1;

    /// @notice Global contract configuration
    ContractConfig public config;

    mapping(uint256 => address) public admins;

    constructor() ERC1155("") {}

    function isAdminOrRole(address user, uint256 tokenId, uint256 role) external view returns (bool) {
        if (admins[tokenId] == user && role == PERMISSION_BIT_ADMIN) {
            return true;
        } else {
            return false;
        }
    }

    function _tokenExists(uint256 tokenId) internal view returns (bool) {
        return admins[tokenId] != address(0);
    }

    function createToken(uint256 tokenId, address creator) external {
        admins[tokenId] = creator;
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, IZoraCreator1155) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function mint(address to, uint256 id, uint256 amount, bytes memory data) external {
        if (!_tokenExists(id)) {
            revert("Token does not exist");
        }

        _mint(to, id, amount, data);
    }

    function _setFundsRecipient(address payable fundsRecipient) internal {
        config.fundsRecipient = fundsRecipient;
    }

    function setFundsRecipient(address payable fundsRecipient) external {
        _setFundsRecipient(fundsRecipient);
    }

    function owner() external view returns (address) {
        return config.owner;
    }

    function _setOwner(address newOwner) internal {
        config.owner = newOwner;
    }

    function setOwner(address newOwner) external {
        _setOwner(newOwner);
    }
}
