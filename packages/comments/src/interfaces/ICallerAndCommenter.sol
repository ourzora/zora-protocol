// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IComments} from "./IComments.sol";

interface ICallerAndCommenter {
    /// @notice Occurs when a signature is invalid
    error InvalidSignature();

    /// @notice Occurs when the deadline has expired
    error ERC2612ExpiredSignature(uint256 deadline);
    /// @notice Occurs when the destination chain ID doesn't match the current chain ID in a permit
    error IncorrectDestinationChain(uint256 wrongDestinationChainId);

    /// @notice Occurs when attempting to upgrade to a contract with a name that doesn't match the current contract's name
    /// @param currentName The name of the current contract
    /// @param newName The name of the contract being upgraded to
    error UpgradeToMismatchedContractName(string currentName, string newName);

    /// @notice Occurs when the commenter address doesn't match the expected address
    /// @param expected The address that was expected to be the commenter
    /// @param actual The actual address that attempted to comment
    error CommenterMismatch(address expected, address actual);

    /// @notice Error thrown when attempting to buy tokens for a collection and tokenId that doesn't have an active sale
    /// @param collection The address of the collection
    /// @param tokenId The ID of the token
    error SaleNotSet(address collection, uint256 tokenId);

    /// @notice Error thrown when the wrong amount of ETH is sent
    /// @param expected The expected amount of ETH
    /// @param actual The actual amount of ETH sent
    error WrongValueSent(uint256 expected, uint256 actual);

    /// @notice Struct representing a permit for timed sale minting and commenting
    struct PermitTimedSaleMintAndComment {
        /// @dev The account that is creating the comment and minting tokens.
        /// Must match the account that is signing the permit
        address commenter;
        /// @dev The number of tokens to mint
        uint256 quantity;
        /// @dev The address of the collection contract to mint from
        address collection;
        /// @dev The token ID to mint
        uint256 tokenId;
        /// @dev The address to receive mint referral rewards, if any
        address mintReferral;
        /// @dev The text of the comment
        string comment;
        /// @dev Permit deadline - execution of permit must be before this timestamp
        uint256 deadline;
        /// @dev Nonce to prevent replay attacks
        bytes32 nonce;
        /// @dev Chain ID where the permit was signed
        uint32 sourceChainId;
        /// @dev Chain ID where the permit should be executed
        uint32 destinationChainId;
    }

    /// @notice Struct representing a permit for buying on secondary market and commenting
    struct PermitBuyOnSecondaryAndComment {
        /// @dev The account that is creating the comment and buying tokens.
        /// Must match the account that is signing the permit
        address commenter;
        /// @dev The number of tokens to buy
        uint256 quantity;
        /// @dev The address of the collection contract to buy from
        address collection;
        /// @dev The token ID to buy
        uint256 tokenId;
        /// @dev The maximum amount of ETH to spend on the purchase
        uint256 maxEthToSpend;
        /// @dev The sqrt price limit for the swap
        uint160 sqrtPriceLimitX96;
        /// @dev The text of the comment
        string comment;
        /// @dev Permit deadline - execution of permit must be before this timestamp
        uint256 deadline;
        /// @dev Nonce to prevent replay attacks
        bytes32 nonce;
        /// @dev Chain ID where the permit was signed
        uint32 sourceChainId;
        /// @dev Chain ID where the permit should be executed
        uint32 destinationChainId;
    }

    enum SwapDirection {
        BUY,
        SELL
    }

    /// @notice Emitted when tokens are bought or sold on the secondary market and a comment is added
    /// @param commentId The unique identifier of the comment
    /// @param commentIdentifier The struct containing details about the comment
    /// @param quantity The number of tokens bought
    /// @param comment The content of the comment
    /// @param swapDirection The direction of the swap
    event SwappedOnSecondaryAndCommented(
        bytes32 indexed commentId,
        IComments.CommentIdentifier commentIdentifier,
        uint256 indexed quantity,
        string comment,
        SwapDirection indexed swapDirection
    );

    /// @notice Emitted when tokens are minted and a comment is added
    /// @param commentId The unique identifier of the comment
    /// @param commentIdentifier The struct containing details about the comment
    /// @param quantity The number of tokens minted
    /// @param text The content of the comment
    event MintedAndCommented(bytes32 indexed commentId, IComments.CommentIdentifier commentIdentifier, uint256 quantity, string text);

    /// @notice Initializes the upgradeable contract
    /// @param owner of the contract that can perform upgrades
    function initialize(address owner) external;

    /// @notice Mints tokens and adds a comment, without needing to pay a spark for the comment.
    /// @dev The payable amount should be the total mint fee. No spark value should be sent.
    /// @param commenter The address of the commenter
    /// @param quantity The number of tokens to mint
    /// @param collection The address of the 1155 collection to mint from
    /// @param tokenId The 1155 token Id to mint
    /// @param mintReferral The address to receive mint referral rewards, if any
    /// @param comment The comment to be added. If empty, no comment will be added.
    /// @return The identifier of the newly created comment
    function timedSaleMintAndComment(
        address commenter,
        uint256 quantity,
        address collection,
        uint256 tokenId,
        address mintReferral,
        string calldata comment
    ) external payable returns (IComments.CommentIdentifier memory);

    /// @notice Mints tokens and adds a comment, without needing to pay a spark for the comment. Attributes the
    /// comment to the signer of the message.  Meant to be used for cross-chain commenting. where a permit
    /// is signed in a chain and then executed in another chain.
    /// @dev The signer must match the commenter field in the permit.
    /// @param permit The PermitTimedSaleMintAndComment struct containing the permit data
    /// @param signature The signature of the permit
    /// @return The identifier of the newly created comment
    function permitTimedSaleMintAndComment(
        PermitTimedSaleMintAndComment calldata permit,
        bytes calldata signature
    ) external payable returns (IComments.CommentIdentifier memory);

    /// @notice Hashes the permit data for a timed sale mint and comment operation
    /// @param permit The PermitTimedSaleMintAndComment struct containing the permit data
    /// @return bytes32 The hash of the permit data for signing
    function hashPermitTimedSaleMintAndComment(PermitTimedSaleMintAndComment memory permit) external view returns (bytes32);

    /// @notice Buys Zora 1155 tokens on secondary market and adds a comment, without needing to pay a spark for the comment.
    /// @param commenter The address of the commenter. Must match the msg.sender.  Commenter will be the recipient of the bought tokens.
    /// @param quantity The number of tokens to buy
    /// @param collection The address of the 1155 collection
    /// @param tokenId The 1155 token Id to buy
    /// @param excessRefundRecipient The address to receive any excess ETH refund
    /// @param maxEthToSpend The maximum amount of ETH to spend on the purchase
    /// @param sqrtPriceLimitX96 The sqrt price limit for the swap
    /// @param comment The comment to be added
    /// @return The identifier of the newly created comment
    /// @dev This function can only be called by the commenter themselves
    function buyOnSecondaryAndComment(
        address commenter,
        uint256 quantity,
        address collection,
        uint256 tokenId,
        address payable excessRefundRecipient,
        uint256 maxEthToSpend,
        uint160 sqrtPriceLimitX96,
        string calldata comment
    ) external payable returns (IComments.CommentIdentifier memory);

    /// @notice Buys tokens on secondary market and adds a comment using a permit
    /// @dev The signer must match the commenter field in the permit.
    /// @param permit The PermitBuyOnSecondaryAndComment struct containing the permit data
    /// @param signature The signature of the permit
    /// @return The identifier of the newly created comment
    function permitBuyOnSecondaryAndComment(
        PermitBuyOnSecondaryAndComment calldata permit,
        bytes calldata signature
    ) external payable returns (IComments.CommentIdentifier memory);

    /// @notice Hashes the permit data for a buy on secondary and comment operation
    /// @param permit The PermitBuyOnSecondaryAndComment struct containing the permit data
    /// @return bytes32 The hash of the permit data for signing
    function hashPermitBuyOnSecondaryAndComment(PermitBuyOnSecondaryAndComment memory permit) external view returns (bytes32);

    /// @notice Sells Zora 1155 tokens on secondary market and adds a comment. A spark needs to be paid for the comment, if a comment
    /// is to be added.
    /// @param commenter The address of the commenter. Must match the msg.sender. Commenter will be the seller of the tokens.
    /// @param quantity The number of tokens to sell
    /// @param collection The address of the 1155 collection
    /// @param tokenId The 1155 token Id to sell
    /// @param recipient The address to receive the ETH proceeds
    /// @param minEthToAcquire The minimum amount of ETH to receive from the sale
    /// @param sqrtPriceLimitX96 The sqrt price limit for the swap
    /// @param comment The comment to be added
    /// @return The identifier of the newly created comment
    /// @dev This function can only be called by the commenter themselves
    function sellOnSecondaryAndComment(
        address commenter,
        uint256 quantity,
        address collection,
        uint256 tokenId,
        address payable recipient,
        uint256 minEthToAcquire,
        uint160 sqrtPriceLimitX96,
        string calldata comment
    ) external payable returns (IComments.CommentIdentifier memory);

    /// @notice Returns the address of the comments contract
    /// @return address The address of the comments contract
    function comments() external view returns (IComments);
}
