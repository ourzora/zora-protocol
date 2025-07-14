// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ICreatorRoyaltiesControl} from "./ICreatorRoyaltiesControl.sol";
import {IMinter1155} from "./IMinter1155.sol";
import {IVersionedContract} from "@zoralabs/shared-contracts/interfaces/IVersionedContract.sol";

/// @notice Factory for 1155 contracts
/// @author @iainnash / @tbtstl
interface IZoraCreator1155Factory is IVersionedContract {
    error Constructor_ImplCannotBeZero();
    error UpgradeToMismatchedContractName(string expected, string actual);
    error ExpectedContractAddressDoesNotMatchCalculatedContractAddress(address expectedContractAddress, address calculcatedContractAddress);

    event FactorySetup();
    event SetupNewContract(
        address indexed newContract,
        address indexed creator,
        address indexed defaultAdmin,
        string contractURI,
        string name,
        ICreatorRoyaltiesControl.RoyaltyConfiguration defaultRoyaltyConfiguration
    );
    event ContractAlreadyExistsSkippingDeploy(address calculatedContractAddress);

    function createContract(
        string memory contractURI,
        string calldata name,
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        address payable defaultAdmin,
        bytes[] calldata setupActions
    ) external returns (address);

    /// @notice creates the contract, using a deterministic address based on the name, contract uri, and defaultAdmin
    function createContractDeterministic(
        string calldata contractURI,
        string calldata name,
        ICreatorRoyaltiesControl.RoyaltyConfiguration calldata defaultRoyaltyConfiguration,
        address payable defaultAdmin,
        bytes[] calldata setupActions
    ) external returns (address);

    function getOrCreateContractDeterministic(
        address expectedContractAddress,
        string calldata newContractURI,
        string calldata name,
        ICreatorRoyaltiesControl.RoyaltyConfiguration calldata defaultRoyaltyConfiguration,
        address payable defaultAdmin,
        bytes[] calldata setupActions
    ) external returns (address calculatedContractAddress);

    function deterministicContractAddress(
        address msgSender,
        string calldata newContractURI,
        string calldata name,
        address contractAdmin
    ) external view returns (address);

    function deterministicContractAddressWithSetupActions(
        address msgSender,
        string calldata newContractURI,
        string calldata name,
        address contractAdmin,
        bytes[] memory setupActions
    ) external view returns (address);

    function defaultMinters() external returns (IMinter1155[] memory minters);

    function initialize(address _owner) external;
}
