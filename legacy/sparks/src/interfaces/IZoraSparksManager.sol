// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import {IZoraSparksAdmin} from "./IZoraSparksAdmin.sol";
import {IZoraSparksMinterManager} from "./IZoraSparksMinterManager.sol";
import {IZoraSparksURIManager} from "./IZoraSparksURIManager.sol";

interface IZoraSparksManager is IZoraSparksAdmin, IZoraSparksURIManager, IZoraSparksMinterManager {
    error UpgradeToMismatchedContractName(string expected, string actual);

    function uri(uint256 tokenId) external view returns (string memory);
}
