// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title IComments
/// @notice Interface for the Comments contract, which allows for comments and sparking (liking with value) on Zora 1155 posts
/// @author oveddan / IsabellaSmallcombe
interface IComments {
    /// @notice Struct representing a unique identifier for a comment
    struct CommentIdentifier {
        address commenter;
        address contractAddress;
        uint256 tokenId;
        bytes32 nonce;
    }

    /// @notice Struct representing a comment
    struct Comment {
        // has this comment been created
        bool exists;
        // total sparks for this comment
        uint256 totalSparks;
    }

    /// @notice Struct representing a permit for creating a comment
    struct PermitComment {
        // The account that is creating the comment.
        // Must match the account that is signing the permit
        address commenter;
        // If the commenter, has a smart wallet, the smart wallet address.
        // If not, zero address.  If set, this address can be checked
        // to see if the token is owned by the smart wallet.
        address commenterSmartWallet;
        // The contract address that is being commented on
        address contractAddress;
        // The token ID that is being commented on
        uint256 tokenId;
        // The comment identifier of the comment being replied to
        CommentIdentifier replyTo;
        // The text of the comment
        string text;
        // Referrer address - will get referral reward from the spark
        address referrer;
        // Permit deadline - execution of permit must be before this timestamp
        uint256 deadline;
        // Nonce to prevent replay attacks
        bytes32 nonce;
        // Chain the permit was signed on
        uint32 sourceChainId;
        // Chain to execute the permit on
        uint32 destinationChainId;
    }

    /// @notice Struct representing a permit for sparking a comment
    struct PermitSparkComment {
        // Comment that is being sparked
        CommentIdentifier comment;
        // Address of the user that is sparking the comment.
        // Must match the address that is signing the permit
        address sparker;
        // Number of sparks to spark
        uint256 sparksQuantity;
        // Permit deadline - execution of permit must be before this timestamp
        uint256 deadline;
        // Nonce to prevent replay attacks
        bytes32 nonce;
        // Referrer address - will get referral reward from the spark
        address referrer;
        // Chain the permit was signed on
        uint32 sourceChainId;
        // Chain to execute the permit on
        uint32 destinationChainId;
    }

    /// @notice Event emitted when a comment is created
    /// @param commentId Unique ID for the comment, generated from a hash of the commentIdentifier
    /// @param commentIdentifier Identifier for the comment, containing details about the comment
    /// @param replyToId Unique ID of the comment being replied to (if any)
    /// @param replyTo Identifier of the comment being replied to (if any)
    /// @param sparksQuantity Number of sparks associated with this comment
    /// @param text The actual text content of the comment
    /// @param timestamp Timestamp when the comment was created
    /// @param referrer Address of the referrer who referred the commenter, if any
    event Commented(
        bytes32 indexed commentId, // Unique ID for the comment, generated from a hash of the commentIdentifier
        CommentIdentifier commentIdentifier, // Identifier for the comment, containing details about the comment
        bytes32 replyToId, // Unique ID of the comment being replied to (if any)
        CommentIdentifier replyTo, // Identifier of the comment being replied to (if any)
        uint256 sparksQuantity, // Number of sparks associated with this comment
        string text, // The actual text content of the comment
        uint256 timestamp, // Timestamp when the comment was created
        address referrer // Address of the referrer who referred the commenter, if any
    );

    /// @notice Event emitted when a comment is backfilled
    /// @param commentId Unique identifier for the backfilled comment
    /// @param commentIdentifier Identifier for the comment
    /// @param text The actual text content of the backfilled comment
    /// @param timestamp Timestamp when the original comment was created
    /// @param originalTransactionId Transaction ID of the original comment (before backfilling)
    event BackfilledComment(
        bytes32 indexed commentId, // Unique identifier for the backfilled comment
        CommentIdentifier commentIdentifier, // Identifier for the comment
        string text, // The actual text content of the backfilled comment
        uint256 timestamp, // Timestamp when the original comment was created
        bytes32 originalTransactionId // Transaction ID of the original comment (before backfilling)
    );

    /// @notice Event emitted when a comment is Sparked
    /// @param commentId Unique identifier of the comment being sparked
    /// @param commentIdentifier Struct containing details about the comment and commenter
    /// @param sparksQuantity Number of sparks added to the comment
    /// @param sparker Address of the user who sparked the comment
    /// @param timestamp Timestamp when the spark action occurred
    /// @param referrer Address of the referrer who referred the sparker, if any
    event SparkedComment(
        bytes32 indexed commentId, // Unique identifier of the comment being sparked
        CommentIdentifier commentIdentifier, // Struct containing details about the comment and commenter
        uint256 sparksQuantity, // Number of sparks added to the comment
        address sparker, // Address of the user who sparked the comment
        uint256 timestamp, // Timestamp when the spark action occurred
        address referrer // Address of the referrer who referred the sparker, if any
    );

    /// @notice Occurs when attempting to add a comment that already exists
    /// @param commentId The unique identifier of the duplicate comment
    error DuplicateComment(bytes32 commentId);

    /// @notice Occurs when the amount of ETH sent with the transaction doesn't match the corresponding sparks quantity
    error IncorrectETHAmountForSparks(uint256 actual, uint256 expected);

    /// @notice Occurs when the commenter address doesn't match the expected address
    /// @param expected The address that was expected to be the commenter
    /// @param actual The actual address that attempted to comment
    error CommenterMismatch(address expected, address actual);

    /// @notice Occurs when attempting to spark a comment without sending at least one spark
    error MustSendAtLeastOneSpark();

    /// @notice Occurs when attempting to submit an empty comment
    error EmptyComment();

    /// @notice Occurs when trying to interact with a comment that doesn't exist
    error CommentDoesntExist();

    /// @notice Occurs when a transfer of funds fails
    error TransferFailed();

    /// @notice Occurs when a user attempts to spark their own comment
    error CannotSparkOwnComment();

    /// @notice Occurs when a function restricted to the Sparks contract is called by another address
    error OnlySparksContract();

    /// @notice Occurs when attempting to upgrade to a contract with a name that doesn't match the current contract's name
    /// @param currentName The name of the current contract
    /// @param newName The name of the contract being upgraded to
    error UpgradeToMismatchedContractName(string currentName, string newName);

    /// @notice Occurs when the lengths of arrays passed to a function do not match
    error ArrayLengthMismatch();

    /// @notice Occurs when the address or token IDs in a comment identifier do not match the expected values
    /// @param commentAddress The address in the comment identifier
    /// @param commentTokenId The token ID in the comment identifier
    /// @param replyAddress The address in the reply identifier
    /// @param replyTokenId The token ID in the reply identifier
    error CommentAddressOrTokenIdsDoNotMatch(address commentAddress, uint256 commentTokenId, address replyAddress, uint256 replyTokenId);

    /// @notice Occurs when the signature is invalid
    error InvalidSignature();

    /// @notice Occurs when the destination chain ID doesn't match the current chain ID in a permit
    error IncorrectDestinationChain(uint256 wrongDestinationChainId);

    /// @notice Occurs when the commenter is not a smart wallet owner
    error NotSmartWalletOwner();

    /// @notice Occurs when the address is not a smart wallet
    error NotSmartWallet();

    /// @notice Occurs when the deadline has expired
    error ERC2612ExpiredSignature(uint256 deadline);

    /// @notice Occurs when the funds recipient does not exist
    error NoFundsRecipient();

    /// @notice Address cannot be zero
    error AddressZero();

    /// @notice Creates a new comment
    /// @param commenter The address of the commenter
    /// @param contractAddress The address of the contract
    /// @param tokenId The token ID
    /// @param text The text content of the comment
    /// @param replyTo The identifier of the comment being replied to (if any)
    /// @param commenterSmartWalletOwner If the commenter has a smart wallet, the smart wallet owner address
    /// @param referrer The address of the referrer (if any)
    /// @return commentIdentifier The identifier of the created comment, including the nonce
    function comment(
        address commenter,
        address contractAddress,
        uint256 tokenId,
        string calldata text,
        CommentIdentifier calldata replyTo,
        address commenterSmartWalletOwner,
        address referrer
    ) external payable returns (CommentIdentifier memory);

    /// @notice Allows another contract to delegate comment creation on behalf of a user
    /// @param commenter The address of the commenter
    /// @param contractAddress The address of the contract
    /// @param tokenId The token ID
    /// @param text The text content of the comment
    /// @param replyTo The identifier of the comment being replied to (if any)
    /// @param commenterSmartWalletOwner If the commenter has a smart wallet, the smart wallet owner address
    /// @param referrer The address of the referrer (if any)
    /// @return commentIdentifier The identifier of the created comment, including the nonce
    function delegateComment(
        address commenter,
        address contractAddress,
        uint256 tokenId,
        string calldata text,
        CommentIdentifier calldata replyTo,
        address commenterSmartWalletOwner,
        address referrer
    ) external payable returns (CommentIdentifier memory, bytes32 commentId);

    function initialize(address commentsAdmin, address backfiller, address[] calldata delegateCommenters) external;

    /// @notice Sparks a comment
    /// @param commentIdentifier The identifier of the comment to spark
    /// @param sparksQuantity The quantity of sparks to send
    /// @param referrer The referrer of the comment
    function sparkComment(CommentIdentifier calldata commentIdentifier, uint256 sparksQuantity, address referrer) external payable;

    /// @notice Returns the value of a single spark
    /// @return The value of a single spark
    function sparkValue() external view returns (uint256);

    /// @notice Hashes a comment identifier to generate a unique ID
    /// @param commentIdentifier The comment identifier to hash
    /// @return The hashed comment identifier
    function hashCommentIdentifier(CommentIdentifier calldata commentIdentifier) external view returns (bytes32);

    /// @notice Returns the next nonce for comment creation
    /// @return The next nonce
    function nextNonce() external view returns (bytes32);

    /// @notice Returns the implementation address of the contract
    /// @return The implementation address
    function implementation() external view returns (address);

    /// @notice Returns the total number of sparks a given comment has received
    /// @param commentIdentifier The identifier of the comment
    /// @return The total number of sparks a comment has received
    function commentSparksQuantity(CommentIdentifier memory commentIdentifier) external view returns (uint256);

    /// @notice Hashes a comment identifier and checks if a comment exists with that id
    /// @param commentIdentifier The comment identifier to check
    /// @return commentId The hashed comment identifier
    /// @return exists Whether the comment exists
    function hashAndCheckCommentExists(CommentIdentifier memory commentIdentifier) external view returns (bytes32 commentId, bool exists);

    /// @notice Validates that a comment exists and returns its ID
    /// @param commentIdentifier The comment identifier to validate
    /// @return commentId The hashed comment identifier
    function hashAndValidateCommentExists(CommentIdentifier memory commentIdentifier) external view returns (bytes32 commentId);

    /// @notice Hashes a permit comment struct for signing
    /// @param permit The permit comment struct
    /// @return The hash to sign
    function hashPermitComment(PermitComment calldata permit) external view returns (bytes32);

    /// @notice Creates a comment on behalf of another account using a signed message
    /// @param permit The permit that was signed off-chain on the source chain
    /// @param signature The signature of the permit comment
    function permitComment(PermitComment calldata permit, bytes calldata signature) external payable;

    /// @notice Hashes a permit spark comment struct for signing
    /// @param permit The permit spark comment struct
    /// @return The hash to sign
    function hashPermitSparkComment(PermitSparkComment calldata permit) external view returns (bytes32);

    /// @notice Sparks a comment on behalf of another account using a signed message
    /// @param permit The permit spark comment struct
    /// @param signature The signature of the permit
    function permitSparkComment(PermitSparkComment calldata permit, bytes calldata signature) external payable;

    /// @notice Backfills comments created by other contracts
    /// @param commentIdentifiers Array of comment identifiers
    /// @param texts Array of comment texts
    /// @param timestamps Array of comment timestamps
    /// @param originalTransactionHashes Array of original transaction hashes
    function backfillBatchAddComment(
        CommentIdentifier[] calldata commentIdentifiers,
        string[] calldata texts,
        uint256[] calldata timestamps,
        bytes32[] calldata originalTransactionHashes
    ) external;
}
