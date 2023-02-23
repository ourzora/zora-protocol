// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ICreatorRoyaltiesControl} from "./ICreatorRoyaltiesControl.sol";
import {IMinter1155} from "./IMinter1155.sol";
import {IVersionedContract} from "./IVersionedContract.sol";

interface IZoraCreator1155Factory is IVersionedContract {
    event FactorySetup();
    error Constructor_ImplCannotBeZero();

    function createContract(
        string memory contractURI,
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        address defaultAdmin,
        bytes[] calldata setupActions
    ) external returns (address);

    event SetupNewContract(
        address newContract,
        address creator,
        address defaultAdmin,
        string contractURI,
        ICreatorRoyaltiesControl.RoyaltyConfiguration defaultRoyaltyConfiguration
    );

    function defaultMinters() external returns (IMinter1155[] memory minters);

    function initialize(address _owner) external;
}
