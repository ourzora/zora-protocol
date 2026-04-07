// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IWETH} from "@zoralabs/shared-contracts/interfaces/IWETH.sol";
import {INonfungiblePositionManager} from "@zoralabs/shared-contracts/interfaces/uniswap/INonfungiblePositionManager.sol";

interface IRoyalties {
    /// @notice RoyaltyClaim Event
    /// @param collection The 1155 collection address
    /// @param tokenId The 1155 collection token ID
    /// @param creator The creator address
    /// @param recipient The recipient address
    /// @param positionAddress The Uniswap V3 position address
    /// @param positionId The Uniswap V3 position id
    /// @param token0 Token0 address
    /// @param token0Amount The token0 amount
    /// @param token1 Token1 address
    /// @param token1Amount The token1 amount
    event RoyaltyClaim(
        address indexed collection,
        uint256 indexed tokenId,
        address indexed creator,
        address recipient,
        address positionAddress,
        uint256 positionId,
        address token0,
        uint256 token0Amount,
        address token1,
        uint256 token1Amount
    );

    /// @notice UniswapTokenDeposited Event
    /// @param erc20zAddress The ERC20Z address
    /// @param positionAddress The Uniswap V3 position address
    /// @param positionId The Uniswap V3 position id
    event RoyaltyDeposit(address indexed erc20zAddress, address positionAddress, uint256 positionId);

    /// @notice Only ERC20z address can call this function
    error OnlyErc20z();

    /// @notice Params cannot be zero
    error ParamsCannotBeZero();

    /// @notice Creator must be set
    error CreatorMustBeSet();

    /// @notice Only creator can call
    error OnlyCreatorCanCall();

    /// @notice Address cannot be zero
    error AddressCannotBeZero();

    /// @notice Only WETH can send ETH
    error OnlyWeth();

    /// @notice ERC721 Sender for Royalties needs to be the NFT Position Manager
    error ERC721SenderRoyaltiesNeedsToBePositionManager();

    /// @notice If the contract is already initialized
    error AlreadyInitialized();

    /// @notice if a zero address is passed
    error AddressZero();

    /// @notice Claim royalties for a creator
    /// @param erc20z The associated erc20z token
    /// @param recipient The recipient address
    function claim(address erc20z, address payable recipient) external;

    /// @notice Claim royalties for a creator
    /// @param erc20z The associated erc20z token
    function claimFor(address erc20z) external;

    /// @notice Returns the total recipient fee based on a given amount
    /// @param amount the amount
    function getFee(uint256 amount) external view returns (uint256);

    /// @notice The address of WETH
    function WETH() external returns (IWETH);

    /// @notice The Uniswap V3 nonfungible position manager address
    function nonfungiblePositionManager() external returns (INonfungiblePositionManager);

    /// @notice The total unclaimed fees for an ERC20z token
    /// @param erc20z The ERC20z address
    function getUnclaimedFees(address erc20z) external view returns (UnclaimedFees memory);

    /// @notice The total unclaimed fees for a batch of ERC20z tokens
    /// @param erc20z The ERC20z addresses
    function getUnclaimedFeesBatch(address[] calldata erc20z) external view returns (UnclaimedFees[] memory);

    struct UnclaimedFees {
        address token0;
        address token1;
        uint128 token0Amount;
        uint128 token1Amount;
    }
}
