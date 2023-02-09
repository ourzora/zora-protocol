// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ICreatorRoyaltiesControl} from "./ICreatorRoyaltiesControl.sol";

interface IZoraCreator1155Factory {
    event FactorySetup();
    error Constructor_ImplCannotBeZero();

    function createContract(
        string memory contractURI,
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        address defaultAdmin,
        bytes[] calldata setupActions
    ) external returns (address);
}
