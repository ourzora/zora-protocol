// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC1155} from "@openzeppelin/contracts/interfaces/IERC1155.sol";
import {IZoraCreator1155TypesV1} from "../../src/interfaces/IZoraCreator1155TypesV1.sol";

// For testing without getCreatorRewardRecipient
interface IZoraCreator1155 is IERC1155, IZoraCreator1155TypesV1 {
    function isAdminOrRole(address user, uint256 tokenId, uint256 role) external view returns (bool);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function config() external view returns (address owner, uint96 __gap1, address payable fundsRecipient, uint96 __gap2, address transferHook, uint96 __gap3);

    function setFundsRecipient(address payable fundsRecipient) external;
}
