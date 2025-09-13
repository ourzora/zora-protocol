// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolKeyStruct} from "./ICoin.sol";
import {IDeployedCoinVersionLookup} from "./IDeployedCoinVersionLookup.sol";

interface IZoraFactory is IDeployedCoinVersionLookup {
    /// @notice Emitted when a coin is created
    /// @param caller The msg.sender address
    /// @param payoutRecipient The address of the creator payout recipient
    /// @param platformReferrer The address of the platform referrer
    /// @param currency The address of the currency
    /// @param uri The URI of the coin
    /// @param name The name of the coin
    /// @param symbol The symbol of the coin
    /// @param coin The address of the coin
    /// @param pool The address of the pool
    /// @param version The coin contract version
    event CoinCreated(
        address indexed caller,
        address indexed payoutRecipient,
        address indexed platformReferrer,
        address currency,
        string uri,
        string name,
        string symbol,
        address coin,
        address pool,
        string version
    );

    /// @notice Emitted when a coin is created
    /// @param caller The msg.sender address
    /// @param payoutRecipient The address of the creator payout recipient
    /// @param platformReferrer The address of the platform referrer
    /// @param currency The address of the currency
    /// @param uri The URI of the coin
    /// @param name The name of the coin
    /// @param symbol The symbol of the coin
    /// @param coin The address of the coin
    /// @param poolKey The uniswap v4 pool key
    /// @param version The coin contract version
    event CoinCreatedV4(
        address indexed caller,
        address indexed payoutRecipient,
        address indexed platformReferrer,
        address currency,
        string uri,
        string name,
        string symbol,
        address coin,
        PoolKey poolKey,
        bytes32 poolKeyHash,
        string version
    );

    /// @notice Emitted when a creator coin is created
    /// @param caller The msg.sender address
    /// @param payoutRecipient The address of the creator payout recipient
    /// @param platformReferrer The address of the platform referrer
    /// @param currency The address of the currency
    /// @param uri The URI of the coin
    /// @param name The name of the coin
    /// @param symbol The symbol of the coin
    /// @param coin The address of the coin
    /// @param poolKey The uniswap v4 pool key
    /// @param version The coin contract version
    event CreatorCoinCreated(
        address indexed caller,
        address indexed payoutRecipient,
        address indexed platformReferrer,
        address currency,
        string uri,
        string name,
        string symbol,
        address coin,
        PoolKey poolKey,
        bytes32 poolKeyHash,
        string version
    );

    /// @notice Thrown when ETH is sent with a transaction but the currency is not WETH
    error EthTransferInvalid();

    /// @notice Thrown when the hook is invalid
    error InvalidHook();

    /// @notice Occurs when attempting to upgrade to a contract with a name that doesn't match the current contract's name
    /// @param currentName The name of the current contract
    /// @param newName The name of the contract being upgraded to
    error UpgradeToMismatchedContractName(string currentName, string newName);

    /// @notice Thrown when a method is deprecated
    error Deprecated();

    /// @notice Thrwon when an invalid config version is provided
    error InvalidConfig();

    /// @notice Creates a new creator coin contract
    /// @param payoutRecipient The recipient of creator reward payouts; this can be updated by an owner
    /// @param owners The list of addresses that will be able to manage the coin's payout address and metadata uri
    /// @param uri The coin metadata uri
    /// @param name The name of the coin
    /// @param symbol The symbol of the coin
    /// @param poolConfig The config parameters for the coin's pool
    /// @param platformReferrer The address of the platform referrer
    /// @param coinSalt The salt used to deploy the coin
    function deployCreatorCoin(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        bytes32 coinSalt
    ) external returns (address);

    /// @notice Creates a new coin contract with an optional hook that runs after the coin is deployed.
    /// Requires a salt to be specified, which enabled the coin to be deployed deterministically, and at
    /// a predictable address.
    /// @param payoutRecipient The recipient of creator reward payouts; this can be updated by an owner
    /// @param owners The list of addresses that will be able to manage the coin's payout address and metadata uri
    /// @param uri The coin metadata uri
    /// @param name The name of the coin
    /// @param symbol The symbol of the coin
    /// @param poolConfig The config parameters for the coin's pool
    /// @param platformReferrer The address of the platform referrer
    /// @param postDeployHook The address of the hook to run after the coin is deployed
    /// @param postDeployHookData The data to pass to the hook
    /// @return coin The address of the deployed coin
    /// @return postDeployHookDataOut The data returned by the hook
    function deploy(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        address postDeployHook,
        bytes calldata postDeployHookData,
        bytes32 coinSalt
    ) external payable returns (address coin, bytes memory postDeployHookDataOut);

    /// @notice Predicts the address of a coin contract that will be deployed with the given parameters
    /// @param msgSender The address of the msg.sender
    /// @param name The name of the coin
    /// @param symbol The symbol of the coin
    /// @param poolConfig The pool config
    /// @param platformReferrer The platform referrer
    /// @param coinSalt The salt used to deploy the coin
    /// @return The address of the coin contract
    function coinAddress(
        address msgSender,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        bytes32 coinSalt
    ) external view returns (address);

    /// @dev Deprecated: use `deploy` instead that has a salt and hook specified
    function deploy(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        uint256 orderSize
    ) external payable returns (address, uint256);

    /// @dev Deprecated: use `deploy` instead that has a salt and hook specified
    function deployWithHook(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        address hook,
        bytes calldata hookData
    ) external payable returns (address coin, bytes memory hookDataOut);

    /// @notice The implementation address of the factory contract
    function implementation() external view returns (address);

    /// @notice The address of the latest coin hook
    function hook() external view returns (address);

    /// @notice The address of the latest content coin hook
    function contentCoinHook() external view returns (address);

    /// @notice The address of the latestcreator coin hook
    function creatorCoinHook() external view returns (address);

    /// @notice The address of the Zora hook registry
    function zoraHookRegistry() external view returns (address);
}
