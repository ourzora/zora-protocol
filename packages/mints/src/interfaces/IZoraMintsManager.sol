// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IZoraMintsAdmin} from "./IZoraMintsAdmin.sol";
import {IZoraMintsMinterManager} from "./IZoraMintsMinterManager.sol";
import {IZoraMintsURIManager} from "./IZoraMintsURIManager.sol";

interface IZoraMintsManager is IZoraMintsAdmin, IZoraMintsURIManager, IZoraMintsMinterManager {
    error UpgradeToMismatchedContractName(string expected, string actual);

    function uri(uint256 tokenId) external view returns (string memory);
}
