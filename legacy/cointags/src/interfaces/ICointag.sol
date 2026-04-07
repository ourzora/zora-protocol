// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IUniswapV3Pool} from "@zoralabs/shared-contracts/interfaces/uniswap/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ICointag - Interface for the Cointag Protocol
/// @notice Cointag is a protocol that enables a portion of creator rewards earned from Zora posts to be used to buy and burn an ERC20 token.
/// @dev Cointags are created for each combination of creator reward recipient, ERC20 token, and Uniswap V3 pool.
/// This contract is upgradeable by the creator using UUPS pattern and controlled by an UpgradeGate.
///
/// The protocol works by:
/// 1. Receiving creator rewards from Zora posts.
/// 2. Using a portion of those rewards to buy tokens from a Uniswap V3 pool
/// 3. Burning the purchased tokens (or sending to dead address if burn fails)
/// 4. Sending remaining ETH to the creator reward recipient
interface ICointag {
    /// @notice Emitted when a new Cointag contract is initialized
    /// @param creatorRewardRecipient The address that will receive creator rewards
    /// @param erc20 The address of the ERC20 token that will be bought and burned
    /// @param pool The Uniswap V3 pool used for swapping WETH to ERC20
    /// @param percentageToBuyBurn The percentage of rewards that will be used to buy and burn tokens
    event Initialized(address creatorRewardRecipient, address erc20, address pool, uint256 percentageToBuyBurn);

    /// @notice Emitted when tokens are bought and burned
    /// @param amountERC20Received The amount of ERC20 tokens received from the swap
    /// @param amountERC20Burned The amount of ERC20 tokens successfully burned
    /// @param amountETHSpent The amount of ETH spent on buying tokens
    /// @param amountETHToCreator The amount of ETH sent to creator
    /// @param totalETHReceived The total amount of ETH received in this transaction
    /// @param buyFailureError The error message if the buy operation failed, empty if successful
    /// @param burnFailureError The error message if the burn operation failed, empty if successful
    event BuyBurn(
        uint256 amountERC20Received,
        uint256 amountERC20Burned,
        uint256 amountETHSpent,
        uint256 amountETHToCreator,
        uint256 totalETHReceived,
        bytes buyFailureError,
        bytes burnFailureError
    );

    /// @custom:storage-location erc7201:cointag.storage.CointagStorage
    struct CointagStorageV1 {
        address creatorRewardRecipient;
        IERC20 erc20;
        IUniswapV3Pool pool;
        uint256 percentageToBuyBurn;
    }

    function config() external view returns (CointagStorageV1 memory cointagStorage);

    /// @notice Emitted when ETH is received by the contract
    event EthReceived(uint256 indexed amount, address indexed sender);

    /// @notice Default for UnknownBurnError when a burn error is caught
    error UnknownBurnError();

    /// @notice Default for UnknownSwapError when a swap error is caught
    error UnknownSwapError();

    /// @notice Thrown when a function is called by an address other than the protocol rewards or WETH contract
    error OnlyProtocolRewardsOrWeth();

    /// @notice Thrown when a function is called by an address other than the pool
    error OnlyPool();

    /// @notice Thrown when the address is the zero address
    error AddressZero();

    /// @notice Thrown when the pool needs at least one token to be WETH
    error PoolNeedsOneTokenToBeWETH();

    /// @notice Thrown when the upgrade path is invalid
    error InvalidUpgradePath(address oldImpl, address newImpl);

    /// @notice Thrown when the upgrade to a new implementation has a mismatched contract name
    error UpgradeToMismatchedContractName(string current, string newName);

    /// @notice Thrown when the pool is not a valid Uniswap V3 pool
    error NotUniswapV3Pool();

    /// @notice Pulls rewards from protocol rewards and pushes them through the distribution flow
    function pull() external;

    /// @notice Initializes the Cointag contract
    /// @param _creatorRewardRecipient The address that will receive creator rewards
    /// @param _pool The Uniswap V3 pool used for swapping WETH to ERC20
    /// @param _percentageToBuyBurn The percentage of rewards that will be used to buy and burn tokens
    function initialize(address _creatorRewardRecipient, address _pool, uint256 _percentageToBuyBurn) external;

    /// @notice Distributes ETH currently held by the contract to buy and burn tokens and pay the creator
    /// @dev This function is called automatically when pulling.
    /// but can also be called manually to distribute any ETH held by the contract if it was sent separately.
    function distribute() external;

    /// @notice Returns the pool
    function pool() external returns (IUniswapV3Pool);

    /// @notice Returns the ERC20 token that will be bought and burned
    function erc20() external returns (IERC20);

    /// @notice Returns the contract name
    function contractName() external view returns (string memory);

    /// @notice Returns the implementation of the contract
    function implementation() external view returns (address);
}
