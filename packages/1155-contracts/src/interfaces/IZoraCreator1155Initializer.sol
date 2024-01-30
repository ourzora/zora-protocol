// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";

interface IZoraCreator1155Initializer {
    function initialize(
        string memory contractName,
        string memory newContractURI,
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        address payable defaultAdmin,
        bytes[] calldata setupActions
    ) external;
}
