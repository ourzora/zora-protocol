// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ICointag} from "./ICointag.sol";

/// @title ICointagFactory
/// @notice Interface for the Cointag factory implementation
/// @dev Handles creation and management of Cointag contracts
interface ICointagFactory {
    /// @notice Thrown when an address parameter is zero
    error AddressZero();

    /// @notice Thrown when the created Cointag address doesn't match the expected address
    /// @param expected The address that was expected
    /// @param actual The address that was actually created
    error UnexpectedCointagAddress(address expected, address actual);

    /// @notice Occurs when attempting to upgrade to a contract with a name that doesn't match the current contract's name
    /// @param currentName The name of the current contract
    /// @param newName The name of the contract being upgraded to
    error UpgradeToMismatchedContractName(string currentName, string newName);

    /// @notice Emitted when a new Cointag contract is created
    /// @param cointag Address of the newly created Cointag contract
    /// @param creatorRewardRecipient Address that will receive creator rewards
    /// @param erc20 Address of the ERC20 token associated with the Cointag
    /// @param pool Address of the pool contract
    /// @param percentageToBuyBurn Percentage of tokens to buy and burn
    /// @param saltSource Additional data used to generate the deterministic address
    event SetupNewCointag(
        address indexed cointag,
        address indexed creatorRewardRecipient,
        address indexed erc20,
        address pool,
        uint256 percentageToBuyBurn,
        bytes saltSource
    );

    /// @notice Initializes the contract
    /// @param _defaultOwner Address of the initial contract owner
    function initialize(address _defaultOwner) external;

    /// @notice Returns the implementation address of the proxy
    /// @return The address of the implementation contract
    function implementation() external view returns (address);

    /// @notice Returns the name of the contract
    /// @return The contract name as a string
    function contractName() external pure returns (string memory);

    /// @notice Returns the URI of the contract
    /// @return The contract URI as a string
    function contractURI() external pure returns (string memory);

    /// @notice Creates a new Cointag contract or returns existing one if already deployed. Contract address is deterministic,
    /// based on the creatorRewardRecipient, pool, percentageToBuyBurn, and saltSource, independent of the implementation address or code version.
    /// @param _creatorRewardRecipient Address that will receive creator rewards
    /// @param _pool Address of the pool contract
    /// @param _percentageToBuyBurn Percentage of tokens to buy and burn
    /// @param saltSource Additional data used to generate the deterministic address
    /// @return The Cointag contract instance
    function getOrCreateCointag(
        address _creatorRewardRecipient,
        address _pool,
        uint256 _percentageToBuyBurn,
        bytes calldata saltSource
    ) external returns (ICointag);

    /// @notice Predicts the address where a Cointag contract would be deployed
    /// @param _creatorRewardRecipient Address that will receive creator rewards
    /// @param _pool Address of the pool contract
    /// @param _percentageToBuyBurn Percentage of tokens to buy and burn
    /// @param saltSource Additional data used to generate the deterministic address
    /// @return The predicted address of the Cointag contract
    function getCointagAddress(
        address _creatorRewardRecipient,
        address _pool,
        uint256 _percentageToBuyBurn,
        bytes calldata saltSource
    ) external view returns (address);

    /// @notice Creates a new Cointag contract or returns existing one if already deployed, verifying the address matches expected
    /// @param _creatorRewardRecipient Address that will receive creator rewards
    /// @param _pool Address of the pool contract
    /// @param _percentageToBuyBurn Percentage of tokens to buy and burn
    /// @param saltSource Additional data used to generate the deterministic address
    /// @param expectedAddress The address where the Cointag is expected to be deployed
    /// @return The Cointag contract instance
    function getOrCreateCointagAtExpectedAddress(
        address _creatorRewardRecipient,
        address _pool,
        uint256 _percentageToBuyBurn,
        bytes calldata saltSource,
        address expectedAddress
    ) external returns (ICointag);
}
