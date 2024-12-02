// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title CommentsImplConstants
/// @notice Constants for the CommentsImpl contract
/// @author oveddan / IsabellaSmallcombe
contract CommentsImplConstants {
    /// @notice this is the zora creator multisig that can upgrade the contract
    bytes32 public constant BACKFILLER_ROLE = keccak256("BACKFILLER_ROLE");
    /// @notice allows to delegate comment
    bytes32 public constant DELEGATE_COMMENTER = keccak256("DELEGATE_COMMENTER");
    /// @notice permission bit for admin
    uint256 public constant PERMISSION_BIT_ADMIN = 2 ** 1;
    /// @notice Zora reward percentage
    uint256 public constant ZORA_REWARD_PCT = 10;
    /// @notice referrer reward percentage
    uint256 public constant REFERRER_REWARD_PCT = 20;
    /// @notice Zora reward percentage when there is no referrer
    uint256 public constant ZORA_REWARD_NO_REFERRER_PCT = 30;
    /// @notice BPS to percent conversion
    uint256 internal constant BPS_TO_PERCENT_2_DECIMAL_PERCISION = 100;
    /// @notice domain name for comments
    string public constant DOMAIN_NAME = "Comments";
    /// @notice domain version for comments
    string public constant DOMAIN_VERSION = "1";
    /// @notice Zora reward reason
    bytes4 constant ZORA_REWARD_REASON = bytes4(keccak256("zoraRewardForCommentDeposited()"));
    /// @notice referrer reward reason
    bytes4 constant REFERRER_REWARD_REASON = bytes4(keccak256("referrerRewardForCommentDeposited()"));
    /// @notice sparks recipient reward reason
    bytes4 constant SPARKS_RECIPIENT_REWARD_REASON = bytes4(keccak256("sparksRecipientRewardForCommentDeposited()"));
    /// @notice permint comment domain
    bytes32 constant PERMIT_COMMENT_DOMAIN =
        keccak256(
            "PermitComment(address contractAddress,uint256 tokenId,address commenter,CommentIdentifier replyTo,string text,uint256 deadline,bytes32 nonce,address commenterSmartWallet,address referrer,uint32 sourceChainId,uint32 destinationChainId)CommentIdentifier(address contractAddress,uint256 tokenId,address commenter,bytes32 nonce)"
        );
    /// @notice comment identifier domain
    bytes32 constant COMMENT_IDENTIFIER_DOMAIN = keccak256("CommentIdentifier(address contractAddress,uint256 tokenId,address commenter,bytes32 nonce)");
    /// @notice permit spark comment domain
    bytes32 constant PERMIT_SPARK_COMMENT_DOMAIN =
        keccak256(
            "PermitSparkComment(CommentIdentifier comment,address sparker,uint256 sparksQuantity,uint256 deadline,bytes32 nonce,address referrer,uint32 sourceChainId,uint32 destinationChainId)CommentIdentifier(address contractAddress,uint256 tokenId,address commenter,bytes32 nonce)"
        );
}
