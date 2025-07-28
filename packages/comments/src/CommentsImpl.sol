// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IHasContractName} from "@zoralabs/shared-contracts/interfaces/IContractMetadata.sol";
import {ContractVersionBase} from "./version/ContractVersionBase.sol";
import {IZoraCreator1155} from "./interfaces/IZoraCreator1155.sol";
import {IComments} from "./interfaces/IComments.sol";
import {ICoinComments} from "./interfaces/ICoinComments.sol";
import {IProtocolRewards} from "@zoralabs/shared-contracts/interfaces/IProtocolRewards.sol";
import {UnorderedNoncesUpgradeable} from "@zoralabs/shared-contracts/utils/UnorderedNoncesUpgradeable.sol";
import {EIP712UpgradeableWithChainId} from "./utils/EIP712UpgradeableWithChainId.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IMultiOwnable} from "./interfaces/IMultiOwnable.sol";
import {CommentsImplConstants} from "./CommentsImplConstants.sol";

/// @title CommentsImpl
/// @notice Contract for comments and sparking (liking with value) Zora 1155 posts.
/// @dev Implements comment creation, sparking, and backfilling functionality. Implementation contract
/// meant to be used with a UUPS upgradeable proxy contract.
/// @author oveddan / IsabellaSmallcombe
contract CommentsImpl is
    IComments,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ContractVersionBase,
    EIP712UpgradeableWithChainId,
    UnorderedNoncesUpgradeable,
    CommentsImplConstants,
    IHasContractName
{
    /// @notice keccak256(abi.encode(uint256(keccak256("comments.storage.CommentsStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant COMMENTS_STORAGE_LOCATION = 0x9e5d0d3a4c7e8d5b9e8f9d9d5b9e8f9d9d5b9e8f9d9d5b9e8f9d9d5b9e8f9d00;
    /// @notice the spark value to comment
    uint256 public immutable sparkValue;
    /// @notice the address of the protocol rewards contract
    IProtocolRewards public immutable protocolRewards;
    /// @notice account that receives rewards Zora Rewards for from a portion of the sparks value
    address immutable zoraRecipient;

    /// @custom:storage-location erc7201:comments.storage.CommentsStorage
    struct CommentsStorage {
        mapping(bytes32 => Comment) comments;
        // gap that held old zora recipient.
        address __gap;
        // Global autoincrementing nonce
        uint256 nonce;
    }

    function _getCommentsStorage() private pure returns (CommentsStorage storage $) {
        assembly {
            $.slot := COMMENTS_STORAGE_LOCATION
        }
    }

    function comments(bytes32 commentId) internal view returns (Comment storage) {
        return _getCommentsStorage().comments[commentId];
    }

    /// @notice Returns the total number of sparks a given comment has received
    /// @param commentIdentifier The identifier of the comment
    /// @return The total number of sparks a comment has received
    function commentSparksQuantity(CommentIdentifier memory commentIdentifier) external view returns (uint256) {
        return comments(hashCommentIdentifier(commentIdentifier)).totalSparks;
    }

    /// @notice Returns the next nonce for comment creation
    /// @return The next nonce
    function nextNonce() external view returns (bytes32) {
        return bytes32(_getCommentsStorage().nonce);
    }

    /// @notice Returns the implementation address of the contract
    /// @return The implementation address
    function implementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /// @notice Contract constructor
    /// @param _sparkValue The value of a spark
    /// @param _protocolRewards The address of the protocol rewards contract
    /// @param _zoraRecipient The address of the zora recipient
    constructor(uint256 _sparkValue, address _protocolRewards, address _zoraRecipient) {
        if (_protocolRewards == address(0) || _zoraRecipient == address(0)) {
            revert AddressZero();
        }
        _disableInitializers();

        sparkValue = _sparkValue;
        protocolRewards = IProtocolRewards(_protocolRewards);
        zoraRecipient = _zoraRecipient;
    }

    /// @notice Initializes the contract with default admin, backfiller, and delegate commenters
    /// @param defaultAdmin The address of the default admin
    /// @param backfiller The address of the backfiller
    /// @param delegateCommenters The addresses of the delegate commenters
    function initialize(address defaultAdmin, address backfiller, address[] calldata delegateCommenters) public initializer {
        if (defaultAdmin == address(0) || backfiller == address(0)) {
            revert AddressZero();
        }
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __EIP712_init(DOMAIN_NAME, DOMAIN_VERSION);

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(BACKFILLER_ROLE, backfiller);

        for (uint256 i = 0; i < delegateCommenters.length; i++) {
            _grantRole(DELEGATE_COMMENTER, delegateCommenters[i]);
        }
    }

    /// @notice Hashes a comment identifier to generate a unique ID
    /// @param commentIdentifier The comment identifier to hash
    /// @return The hashed comment identifier
    function hashCommentIdentifier(CommentIdentifier memory commentIdentifier) public pure returns (bytes32) {
        return keccak256(abi.encode(commentIdentifier));
    }

    /// @notice Hashes a comment identifier and checks if a comment exists with that id
    /// @param commentIdentifier The comment identifier to check
    /// @return commentId The hashed comment identifier
    /// @return exists Whether the comment exists
    function hashAndCheckCommentExists(CommentIdentifier memory commentIdentifier) public view returns (bytes32 commentId, bool exists) {
        commentId = hashCommentIdentifier(commentIdentifier);
        exists = comments(commentId).exists;
    }

    /// @notice Validates that a comment exists and returns its ID
    /// @param commentIdentifier The comment identifier to validate
    /// @return commentId The hashed comment identifier
    function hashAndValidateCommentExists(CommentIdentifier memory commentIdentifier) public view returns (bytes32 commentId) {
        bool exists;
        (commentId, exists) = hashAndCheckCommentExists(commentIdentifier);
        if (!exists) {
            revert CommentDoesntExist();
        }
    }

    /// @notice Creates a new comment.  Equivalant sparks value in eth must be sent with the transaction.
    /// If not the owner, must send 1 spark.
    /// @param contractAddress The address of the contract
    /// @param tokenId The token ID
    /// @param commenter The address of the commenter
    /// @param text The text content of the comment
    /// @param replyTo The identifier of the comment being replied to (if any)
    /// @param commenterSmartWallet If the commenter has a smart wallet, the smart wallet, which can checked to be the owner or creator of the 1155 token
    /// @param referrer The address of the referrer (if any)
    /// @return commentIdentifier The identifier of the created comment, including the nonce
    function comment(
        address commenter,
        address contractAddress,
        uint256 tokenId,
        string calldata text,
        CommentIdentifier calldata replyTo,
        address commenterSmartWallet,
        address referrer
    ) external payable returns (CommentIdentifier memory commentIdentifier) {
        uint256 sparksQuantity = _getAndValidateSingleSparkQuantityFromValue(msg.value);

        commentIdentifier = _createCommentIdentifier(contractAddress, tokenId, commenter);

        _comment({
            commenter: msg.sender,
            commentIdentifier: commentIdentifier,
            text: text,
            sparksQuantity: sparksQuantity,
            replyTo: replyTo,
            commenterSmartWallet: commenterSmartWallet,
            referrer: referrer,
            mustSendAtLeastOneSpark: true
        });
    }

    // gets the sparks quantity from the value sent with the transaction,
    // ensuring that at most 1 spark is sent.
    function _getAndValidateSingleSparkQuantityFromValue(uint256 value) internal view returns (uint256) {
        if (value == 0) {
            return 0;
        }
        if (value != sparkValue) {
            revert IncorrectETHAmountForSparks(value, sparkValue);
        }
        return 1;
    }

    // Allows another contract to call this function to signify a caller commented, and is trusted
    // to provide who the original commenter was. Allows no sparks to be sent.
    /// @notice Allows another contract to delegate comment creation on behalf of a user
    /// @param commenter The address of the commenter
    /// @param contractAddress The address of the contract
    /// @param tokenId The token ID
    /// @param text The text content of the comment
    /// @param replyTo The identifier of the comment being replied to (if any)
    /// @param referrer The address of the referrer (if any)
    /// @param commenterSmartWalletOwner If the commenter has a smart wallet, the smart wallet owner address
    /// @return commentIdentifier The identifier of the created comment, including the nonce
    function delegateComment(
        address commenter,
        address contractAddress,
        uint256 tokenId,
        string calldata text,
        CommentIdentifier calldata replyTo,
        address commenterSmartWalletOwner,
        address referrer
    ) external payable onlyRole(DELEGATE_COMMENTER) returns (CommentIdentifier memory commentIdentifier, bytes32 commentId) {
        uint256 sparksQuantity = _getAndValidateSingleSparkQuantityFromValue(msg.value);

        commentIdentifier = _createCommentIdentifier(contractAddress, tokenId, commenter);

        commentId = _comment({
            commenter: commentIdentifier.commenter,
            commentIdentifier: commentIdentifier,
            text: text,
            sparksQuantity: sparksQuantity,
            replyTo: replyTo,
            commenterSmartWallet: commenterSmartWalletOwner,
            referrer: referrer,
            mustSendAtLeastOneSpark: false
        });
    }

    function _createCommentIdentifier(address contractAddress, uint256 tokenId, address commenter) private returns (CommentIdentifier memory) {
        CommentsStorage storage $ = _getCommentsStorage();
        return CommentIdentifier({commenter: commenter, contractAddress: contractAddress, tokenId: tokenId, nonce: bytes32($.nonce++)});
    }

    function _comment(
        address commenter,
        CommentIdentifier memory commentIdentifier,
        string memory text,
        uint256 sparksQuantity,
        CommentIdentifier memory replyTo,
        address commenterSmartWallet,
        address referrer,
        bool mustSendAtLeastOneSpark
    ) internal returns (bytes32) {
        if (commentIdentifier.commenter != commenter) {
            revert CommenterMismatch(commentIdentifier.commenter, commenter);
        }

        (bytes32 commentId, bytes32 replyToId) = _validateComment(
            commentIdentifier,
            replyTo,
            text,
            sparksQuantity,
            commenterSmartWallet,
            mustSendAtLeastOneSpark
        );

        _saveCommentAndTransferSparks(commentId, commentIdentifier, text, sparksQuantity, replyToId, replyTo, block.timestamp, referrer);

        return commentId;
    }

    function _validateIdentifiersMatch(CommentIdentifier memory commentIdentifier, CommentIdentifier memory replyTo) internal pure {
        if (commentIdentifier.contractAddress != replyTo.contractAddress || commentIdentifier.tokenId != replyTo.tokenId) {
            revert CommentAddressOrTokenIdsDoNotMatch(commentIdentifier.contractAddress, commentIdentifier.tokenId, replyTo.contractAddress, replyTo.tokenId);
        }
    }

    function _validateComment(
        CommentIdentifier memory commentIdentifier,
        CommentIdentifier memory replyTo,
        string memory text,
        uint256 sparksQuantity,
        address commenterSmartWallet,
        bool mustSendAtLeastOneSpark
    ) internal view returns (bytes32 commentId, bytes32 replyToId) {
        // verify that the commenter specified in the identifier is the one expected
        commentId = hashCommentIdentifier(commentIdentifier);

        if (replyTo.commenter != address(0)) {
            replyToId = hashAndValidateCommentExists(replyTo);
            _validateIdentifiersMatch(commentIdentifier, replyTo);
        }

        if (bytes(text).length == 0) {
            revert EmptyComment();
        }

        _validateCommenterAndSparksQuantity(commentIdentifier, sparksQuantity, mustSendAtLeastOneSpark, commenterSmartWallet);
    }

    function _validateCommenterAndSparksQuantity(
        CommentIdentifier memory commentIdentifier,
        uint256 sparksQuantity,
        bool mustSendAtLeastOneSpark,
        address commenterSmartWallet
    ) internal view {
        if (commenterSmartWallet != address(0)) {
            if (commenterSmartWallet.code.length == 0) {
                revert NotSmartWallet();
            }
            // check if the commenter is a smart wallet owner
            if (!IMultiOwnable(commenterSmartWallet).isOwnerAddress(commentIdentifier.commenter)) {
                revert NotSmartWalletOwner();
            }
        }

        // check that the commenter or smart wallet is a token admin - if they are, then they can comment for free
        if (
            _accountOrSmartWalletIsTokenAdmin(commentIdentifier.contractAddress, commentIdentifier.tokenId, commentIdentifier.commenter, commenterSmartWallet)
        ) {
            return;
        }
        // if they aren't an admin, they must include at least 1 spark
        if (mustSendAtLeastOneSpark && sparksQuantity == 0) {
            revert MustSendAtLeastOneSpark();
        }
    }

    function _getRewardDeposits(
        address sparksRecipient,
        address referrer,
        uint256 sparksValue
    ) internal view returns (address[] memory, uint256[] memory, bytes4[] memory) {
        uint256 recipientCount = referrer != address(0) ? 3 : 2;
        address[] memory recipients = new address[](recipientCount);
        uint256[] memory amounts = new uint256[](recipientCount);
        bytes4[] memory reasons = new bytes4[](recipientCount);

        if (referrer != address(0)) {
            uint256 zoraReward = (ZORA_REWARD_PCT * sparksValue) / BPS_TO_PERCENT_2_DECIMAL_PERCISION;
            recipients[0] = zoraRecipient;
            amounts[0] = zoraReward;
            reasons[0] = ZORA_REWARD_REASON;

            uint256 referrerReward = (REFERRER_REWARD_PCT * sparksValue) / BPS_TO_PERCENT_2_DECIMAL_PERCISION;
            recipients[1] = referrer;
            amounts[1] = referrerReward;
            reasons[1] = REFERRER_REWARD_REASON;

            uint256 sparksRecipientReward = sparksValue - zoraReward - referrerReward;
            recipients[2] = sparksRecipient;
            amounts[2] = sparksRecipientReward;
            reasons[2] = SPARKS_RECIPIENT_REWARD_REASON;
        } else {
            uint256 zoraRewardNoReferrer = (ZORA_REWARD_NO_REFERRER_PCT * sparksValue) / BPS_TO_PERCENT_2_DECIMAL_PERCISION;
            recipients[0] = zoraRecipient;
            amounts[0] = zoraRewardNoReferrer;
            reasons[0] = ZORA_REWARD_REASON;

            uint256 sparkRecipientReward = sparksValue - zoraRewardNoReferrer;
            recipients[1] = sparksRecipient;
            amounts[1] = sparkRecipientReward;
            reasons[1] = SPARKS_RECIPIENT_REWARD_REASON;
        }

        return (recipients, amounts, reasons);
    }

    function _transferSparksValueToRecipient(address sparksRecipient, address referrer, uint256 sparksValue, string memory depositBatchComment) internal {
        (address[] memory recipients, uint256[] memory amounts, bytes4[] memory reasons) = _getRewardDeposits(sparksRecipient, referrer, sparksValue);
        protocolRewards.depositBatch{value: sparksValue}(recipients, amounts, reasons, depositBatchComment);
    }

    function _accountOrSmartWalletIsTokenAdmin(address contractAddress, uint256 tokenId, address user, address smartWallet) internal view returns (bool) {
        bool isCoin = _isCoinComment(contractAddress, tokenId);

        if (isCoin) {
            return ICoinComments(contractAddress).isOwner(user) || (smartWallet != address(0) && ICoinComments(contractAddress).isOwner(smartWallet));
        } else {
            return _isTokenAdmin(contractAddress, tokenId, user) || (smartWallet != address(0) && _isTokenAdmin(contractAddress, tokenId, smartWallet));
        }
    }

    function _isTokenAdmin(address contractAddress, uint256 tokenId, address user) internal view returns (bool) {
        try IZoraCreator1155(contractAddress).isAdminOrRole(user, tokenId, PERMISSION_BIT_ADMIN) returns (bool isAdmin) {
            return isAdmin;
        } catch {
            return false;
        }
    }

    function _isTokenHolder(address contractAddress, uint256 tokenId, address user) internal view returns (bool) {
        try IERC1155(contractAddress).balanceOf(user, tokenId) returns (uint256 balance) {
            return balance > 0;
        } catch {
            return false;
        }
    }

    function _isCoinComment(address contractAddress, uint256 tokenId) internal view returns (bool) {
        return tokenId == 0 && IERC165(contractAddress).supportsInterface(type(ICoinComments).interfaceId);
    }

    function _getCommentSparksRecipient(CommentIdentifier memory commentIdentifier, CommentIdentifier memory replyTo) internal view returns (address) {
        // if there is no reply to, then creator reward recipient of the 1155 token gets the sparks
        // otherwise, the replay to commenter gets the sparks
        if (replyTo.commenter == address(0)) {
            return _getCreatorRewardRecipient(commentIdentifier);
        }

        return replyTo.commenter;
    }

    // executes the comment.  assumes sparks have already been transferred to recipient, and data has been validated
    // assume that the commentId and replyToId are valid
    function _saveCommentAndTransferSparks(
        bytes32 commentId,
        CommentIdentifier memory commentIdentifier,
        string memory text,
        uint256 sparksQuantity,
        bytes32 replyToId,
        CommentIdentifier memory replyToIdentifier,
        uint256 timestamp,
        address referrer
    ) internal {
        _saveComment(commentId, commentIdentifier, text, sparksQuantity, replyToId, replyToIdentifier, timestamp, referrer);
        string memory depositBatchComment = "Comment";

        // update reason if replying to a comment
        if (replyToId != 0) {
            depositBatchComment = "Comment Reply";
        }

        if (sparksQuantity > 0) {
            address sparksRecipient = _getCommentSparksRecipient(commentIdentifier, replyToIdentifier);
            _transferSparksValueToRecipient(sparksRecipient, referrer, sparksQuantity * sparkValue, depositBatchComment);
        }
    }

    function _saveComment(
        bytes32 commentId,
        CommentIdentifier memory commentIdentifier,
        string memory text,
        uint256 sparksQuantity,
        bytes32 replyToId,
        CommentIdentifier memory replyToIdentifier,
        uint256 timestamp,
        address referrer
    ) internal {
        if (comments(commentId).exists) {
            revert DuplicateComment(commentId);
        }
        comments(commentId).exists = true;

        emit Commented(commentId, commentIdentifier, replyToId, replyToIdentifier, sparksQuantity, text, timestamp, referrer);
    }

    /// @notice Sparks a comment.  Equivalant sparks value in eth to sparksQuantity must be sent with the transaction.  Sparking a comment is
    /// similar to liking it, except it is liked with the value of sparks attached.  The spark value gets sent to the commenter, with a fee taken out.
    /// @param commentIdentifier The identifier of the comment to spark
    /// @param sparksQuantity The quantity of sparks to send
    /// @param referrer The referrer of the comment
    function sparkComment(CommentIdentifier calldata commentIdentifier, uint256 sparksQuantity, address referrer) public payable {
        if (sparksQuantity == 0) {
            revert MustSendAtLeastOneSpark();
        }
        _validateSparksQuantityMatchesValue(sparksQuantity, msg.value);
        _sparkComment(commentIdentifier, msg.sender, sparksQuantity, referrer);
    }

    function _validateSparksQuantityMatchesValue(uint256 sparksQuantity, uint256 value) internal view {
        if (value != sparksQuantity * sparkValue) {
            revert IncorrectETHAmountForSparks(value, sparksQuantity * sparkValue);
        }
    }

    function _sparkComment(CommentIdentifier memory commentIdentifier, address sparker, uint256 sparksQuantity, address referrer) internal {
        if (sparker == commentIdentifier.commenter) {
            revert CannotSparkOwnComment();
        }
        bytes32 commentId = hashCommentIdentifier(commentIdentifier);
        if (!comments(commentId).exists) {
            revert CommentDoesntExist();
        }

        comments(commentId).totalSparks += uint256(sparksQuantity);

        _transferSparksValueToRecipient(commentIdentifier.commenter, referrer, sparksQuantity * sparkValue, "Sparked Comment");

        emit SparkedComment(commentId, commentIdentifier, sparksQuantity, sparker, block.timestamp, referrer);
    }

    function _hashCommentIdentifier(CommentIdentifier memory commentIdentifier) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    COMMENT_IDENTIFIER_DOMAIN,
                    commentIdentifier.contractAddress,
                    commentIdentifier.tokenId,
                    commentIdentifier.commenter,
                    commentIdentifier.nonce
                )
            );
    }

    /// @notice Hashes a permit comment struct for signing
    /// @param permit The permit comment struct
    /// @return The hash to sign
    function hashPermitComment(PermitComment calldata permit) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_COMMENT_DOMAIN,
                permit.contractAddress,
                permit.tokenId,
                permit.commenter,
                _hashCommentIdentifier(permit.replyTo),
                keccak256(bytes(permit.text)),
                permit.deadline,
                permit.nonce,
                permit.commenterSmartWallet,
                permit.referrer,
                permit.sourceChainId,
                permit.destinationChainId
            )
        );

        return _hashTypedDataV4(structHash, permit.sourceChainId);
    }

    function _validatePermit(bytes32 digest, bytes32 nonce, bytes calldata signature, address signer, uint256 deadline) internal {
        if (block.timestamp > deadline) {
            revert ERC2612ExpiredSignature(deadline);
        }

        _useCheckedNonce(signer, nonce);
        _validateSignerIsCommenter(digest, signature, signer);
    }

    /// @notice Creates a comment on behalf of another account using a signed message.  Supports cross-chain permits
    /// by specifying the source and destination chain ids.  The signature must be signed by the commenter on the source chain.
    /// @param permit The permit that was signed off-chain on the source chain
    /// @param signature The signature of the permit comment
    function permitComment(PermitComment calldata permit, bytes calldata signature) public payable {
        if (permit.destinationChainId != uint32(block.chainid)) {
            revert IncorrectDestinationChain(permit.destinationChainId);
        }

        bytes32 digest = hashPermitComment(permit);
        _validatePermit(digest, permit.nonce, signature, permit.commenter, permit.deadline);

        CommentIdentifier memory commentIdentifier = _createCommentIdentifier(permit.contractAddress, permit.tokenId, permit.commenter);

        uint256 sparksQuantity = _getAndValidateSingleSparkQuantityFromValue(msg.value);

        (bytes32 commentId, bytes32 replyToId) = _validateComment(
            commentIdentifier,
            permit.replyTo,
            permit.text,
            sparksQuantity,
            permit.commenterSmartWallet,
            true
        );

        _saveCommentAndTransferSparks(commentId, commentIdentifier, permit.text, sparksQuantity, replyToId, permit.replyTo, block.timestamp, permit.referrer);
    }

    /// @notice Hashes a permit spark comment struct for signing
    /// @param permit The permit spark comment struct
    function hashPermitSparkComment(PermitSparkComment calldata permit) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_SPARK_COMMENT_DOMAIN,
                _hashCommentIdentifier(permit.comment),
                permit.sparker,
                permit.sparksQuantity,
                permit.deadline,
                permit.nonce,
                permit.referrer,
                permit.sourceChainId,
                permit.destinationChainId
            )
        );
        return _hashTypedDataV4(structHash, permit.sourceChainId);
    }

    /// @notice Sparks a comment on behalf of another account using a signed message.  Supports cross-chain permits
    /// by specifying the source and destination chain ids.  The signature must be signed by the sparker on the source chain.
    /// @param permit The permit spark comment struct
    /// @param signature The signature of the permit. Must be signed by the sparker.
    function permitSparkComment(PermitSparkComment calldata permit, bytes calldata signature) public payable {
        if (permit.destinationChainId != uint32(block.chainid)) {
            revert IncorrectDestinationChain(permit.destinationChainId);
        }

        bytes32 digest = hashPermitSparkComment(permit);
        _validatePermit(digest, permit.nonce, signature, permit.sparker, permit.deadline);

        if (permit.sparksQuantity == 0) {
            revert MustSendAtLeastOneSpark();
        }

        _validateSparksQuantityMatchesValue(permit.sparksQuantity, msg.value);

        _sparkComment(permit.comment, permit.sparker, permit.sparksQuantity, permit.referrer);
    }

    function _validateSignerIsCommenter(bytes32 digest, bytes calldata signature, address signer) internal view {
        if (!SignatureChecker.isValidSignatureNow(signer, digest, signature)) {
            revert InvalidSignature();
        }
    }

    /// @notice Backfills comments created by other contracts.  Only callable by an account with the backfiller role.
    /// @param commentIdentifiers Array of comment identifiers
    /// @param texts Array of comment texts
    /// @param timestamps Array of comment timestamps
    /// @param originalTransactionHashes Array of original transaction hashes
    function backfillBatchAddComment(
        CommentIdentifier[] calldata commentIdentifiers,
        string[] calldata texts,
        uint256[] calldata timestamps,
        bytes32[] calldata originalTransactionHashes
    ) public onlyRole(BACKFILLER_ROLE) {
        if (commentIdentifiers.length != texts.length || texts.length != timestamps.length || timestamps.length != originalTransactionHashes.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < commentIdentifiers.length; i++) {
            bytes32 commentId = hashCommentIdentifier(commentIdentifiers[i]);

            if (comments(commentId).exists) {
                revert DuplicateComment(commentId);
            }
            comments(commentId).exists = true;

            // create blank replyTo - assume that these were created without replyTo
            emit BackfilledComment(commentId, commentIdentifiers[i], texts[i], timestamps[i], originalTransactionHashes[i]);
        }
    }

    function _getCoinPayoutRecipient(address contractAddress, uint256 tokenId) internal view returns (address) {
        if (_isCoinComment(contractAddress, tokenId)) {
            try ICoinComments(contractAddress).payoutRecipient() returns (address payoutRecipient) {
                return payoutRecipient;
            } catch {
                return address(0);
            }
        }

        return address(0);
    }

    function _getFundsRecipient(address contractAddress) internal view returns (address) {
        try IZoraCreator1155(contractAddress).config() returns (address, uint96, address payable fundsRecipient, uint96, address, uint96) {
            if (fundsRecipient != address(0)) {
                return fundsRecipient;
            }
        } catch {}

        try IZoraCreator1155(contractAddress).owner() returns (address owner) {
            if (owner != address(0)) {
                return owner;
            }
        } catch {}

        return address(0);
    }

    function _tryGetCreatorRewardRecipient(CommentIdentifier memory commentIdentifier) internal view returns (address) {
        try IZoraCreator1155(commentIdentifier.contractAddress).getCreatorRewardRecipient(commentIdentifier.tokenId) returns (address creatorRecipient) {
            return creatorRecipient;
        } catch {
            return address(0);
        }
    }

    function _getCreatorRewardRecipient(CommentIdentifier memory commentIdentifier) internal view returns (address) {
        address payoutRecipient = _getCoinPayoutRecipient(commentIdentifier.contractAddress, commentIdentifier.tokenId);
        if (payoutRecipient != address(0)) {
            return payoutRecipient;
        }

        address creatorRecipient = _tryGetCreatorRewardRecipient(commentIdentifier);
        if (creatorRecipient != address(0)) {
            return creatorRecipient;
        }

        address fundsRecipient = _getFundsRecipient(commentIdentifier.contractAddress);
        if (fundsRecipient != address(0)) {
            return fundsRecipient;
        }
        revert NoFundsRecipient();
    }

    /// @notice Returns the name of the contract
    /// @return The name of the contract
    function contractName() public pure returns (string memory) {
        return "Zora Comments";
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        // check that new implementation's contract name matches the current contract name
        if (!_equals(IHasContractName(newImplementation).contractName(), this.contractName())) {
            revert UpgradeToMismatchedContractName(this.contractName(), IHasContractName(newImplementation).contractName());
        }
    }

    function _equals(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(bytes(a)) == keccak256(bytes(b)));
    }
}
