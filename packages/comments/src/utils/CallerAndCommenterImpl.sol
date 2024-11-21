// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IComments} from "../interfaces/IComments.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {EIP712UpgradeableWithChainId} from "./EIP712UpgradeableWithChainId.sol";
import {UnorderedNoncesUpgradeable} from "@zoralabs/shared-contracts/utils/UnorderedNoncesUpgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IZoraTimedSaleStrategy} from "../interfaces/IZoraTimedSaleStrategy.sol";
import {ICallerAndCommenter} from "../interfaces/ICallerAndCommenter.sol";
import {ContractVersionBase} from "../version/ContractVersionBase.sol";
import {IHasContractName} from "@zoralabs/shared-contracts/interfaces/IContractMetadata.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ISecondarySwap} from "../interfaces/ISecondarySwap.sol";
import {IERC1155} from "@openzeppelin/contracts/interfaces/IERC1155.sol";

/// @title Calls contracts and allows a user to add a comment to be associated with the call.
/// @author oveddan
/// @dev Upgradeable contract.  Is given permission to delegateComment on the Comments contract,
/// meaning it is trusted to indicate who a comment is from.
contract CallerAndCommenterImpl is
    ICallerAndCommenter,
    Ownable2StepUpgradeable,
    EIP712UpgradeableWithChainId,
    UnorderedNoncesUpgradeable,
    ContractVersionBase,
    UUPSUpgradeable,
    IHasContractName
{
    IComments public immutable comments;
    IZoraTimedSaleStrategy public immutable zoraTimedSale;
    ISecondarySwap public immutable secondarySwap;
    uint256 public immutable sparkValue;

    IComments.CommentIdentifier internal emptyCommentIdentifier;

    string constant DOMAIN_NAME = "CallerAndCommenter";
    string constant DOMAIN_VERSION = "1";

    IComments.CommentIdentifier internal emptyReplyTo;

    constructor(address _comments, address _zoraTimedSale, address _swapHelper, uint256 _sparksValue) {
        comments = IComments(_comments);
        zoraTimedSale = IZoraTimedSaleStrategy(_zoraTimedSale);
        secondarySwap = ISecondarySwap(_swapHelper);
        sparkValue = _sparksValue;
        _disableInitializers();
    }

    /// Initializes the upgradeable contract
    /// @param owner of the contract that can perform upgrades
    function initialize(address owner) external initializer {
        __Ownable_init(owner);
        __UUPSUpgradeable_init();
        __EIP712_init(DOMAIN_NAME, DOMAIN_VERSION);
    }

    /// @notice Mints tokens and adds a comment, without needing to pay a spark for the comment.
    /// @dev The payable amount should be the total mint fee.  No spark value should be sent.
    /// @param quantity The number of tokens to mint
    /// @param collection The address of the 1155 collection to mint from
    /// @param tokenId The 1155 token Id to mint
    /// @param mintReferral The address to receive mint referral rewards, if any
    /// @param comment The comment to be added.  If empty, no comment will be added.
    /// @return The identifier of the newly created comment
    function timedSaleMintAndComment(
        address commenter,
        uint256 quantity,
        address collection,
        uint256 tokenId,
        address mintReferral,
        string calldata comment
    ) external payable returns (IComments.CommentIdentifier memory) {
        if (commenter != msg.sender) {
            revert CommenterMismatch(msg.sender, commenter);
        }

        return _timedSaleMintAndComment(commenter, quantity, collection, tokenId, mintReferral, comment);
    }

    function _timedSaleMintAndComment(
        address commenter,
        uint256 quantity,
        address collection,
        uint256 tokenId,
        address mintReferral,
        string calldata comment
    ) internal returns (IComments.CommentIdentifier memory commentIdentifier) {
        zoraTimedSale.mint{value: msg.value}(commenter, quantity, collection, tokenId, mintReferral, "");

        if (bytes(comment).length > 0) {
            bytes32 commentId;
            (commentIdentifier, commentId) = comments.delegateComment(commenter, collection, tokenId, comment, emptyReplyTo, address(0), address(0));

            emit MintedAndCommented(commentId, commentIdentifier, quantity, comment);
        }
    }

    bytes32 constant PERMIT_TIMED_SALE_MINT_AND_COMMENT_DOMAIN =
        keccak256(
            "PermitTimedSaleMintAndComment(address commenter,uint256 quantity,address collection,uint256 tokenId,address mintReferral,string comment,uint256 deadline,bytes32 nonce,uint32 sourceChainId,uint32 destinationChainId)"
        );

    /// @notice Hashes the permit data for a timed sale mint and comment operation
    /// @param permit The PermitTimedSaleMintAndComment struct containing the permit data
    /// @return bytes32 The hash of the permit data for signing
    function hashPermitTimedSaleMintAndComment(PermitTimedSaleMintAndComment memory permit) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TIMED_SALE_MINT_AND_COMMENT_DOMAIN,
                permit.commenter,
                permit.quantity,
                permit.collection,
                permit.tokenId,
                permit.mintReferral,
                keccak256(bytes(permit.comment)),
                permit.deadline,
                permit.nonce,
                permit.sourceChainId,
                permit.destinationChainId
            )
        );

        return _hashTypedDataV4(structHash, permit.sourceChainId);
    }

    function _validateSignature(bytes32 digest, bytes calldata signature, address signer) internal view {
        if (!SignatureChecker.isValidSignatureNow(signer, digest, signature)) {
            revert InvalidSignature();
        }
    }

    function _validateAndUsePermit(
        bytes32 digest,
        bytes32 nonce,
        bytes calldata signature,
        address signer,
        uint256 deadline,
        uint32 destinationChainId
    ) internal {
        if (block.timestamp > deadline) {
            revert ERC2612ExpiredSignature(deadline);
        }

        if (destinationChainId != uint32(block.chainid)) {
            revert IncorrectDestinationChain(destinationChainId);
        }

        _useCheckedNonce(signer, nonce);
        _validateSignature(digest, signature, signer);
    }

    /// @notice Mints tokens and adds a comment, without needing to pay a spark for the comment.  Attributes the
    /// comment to the signer of the message.  Meant to be used for cross-chain commenting. where a permit
    /// @dev The signer must match the commenter field in the permit.
    /// @param permit The PermitTimedSaleMintAndComment struct containing the permit data
    /// @param signature The signature of the permit
    /// @return The identifier of the newly created comment
    function permitTimedSaleMintAndComment(
        PermitTimedSaleMintAndComment calldata permit,
        bytes calldata signature
    ) public payable returns (IComments.CommentIdentifier memory) {
        bytes32 digest = hashPermitTimedSaleMintAndComment(permit);

        _validateAndUsePermit(digest, permit.nonce, signature, permit.commenter, permit.deadline, permit.destinationChainId);

        return _timedSaleMintAndComment(permit.commenter, permit.quantity, permit.collection, permit.tokenId, permit.mintReferral, permit.comment);
    }

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
    ) external payable returns (IComments.CommentIdentifier memory) {
        if (commenter != msg.sender) {
            revert CommenterMismatch(msg.sender, commenter);
        }

        return _buyOnSecondaryAndComment(commenter, quantity, collection, tokenId, excessRefundRecipient, maxEthToSpend, sqrtPriceLimitX96, comment);
    }

    function _buyOnSecondaryAndComment(
        address commenter,
        uint256 quantity,
        address collection,
        uint256 tokenId,
        address payable excessRefundRecipient,
        uint256 maxEthToSpend,
        uint160 sqrtPriceLimitX96,
        string calldata comment
    ) internal returns (IComments.CommentIdentifier memory commentIdentifier) {
        address erc20zAddress = zoraTimedSale.sale(collection, tokenId).erc20zAddress;
        if (erc20zAddress == address(0)) {
            revert SaleNotSet(collection, tokenId);
        }

        secondarySwap.buy1155{value: msg.value}({
            erc20zAddress: erc20zAddress,
            num1155ToBuy: quantity,
            recipient: payable(commenter),
            excessRefundRecipient: excessRefundRecipient,
            maxEthToSpend: maxEthToSpend,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        if (bytes(comment).length > 0) {
            bytes32 commentId;
            (commentIdentifier, commentId) = comments.delegateComment(commenter, collection, tokenId, comment, emptyReplyTo, address(0), address(0));

            emit SwappedOnSecondaryAndCommented(commentId, commentIdentifier, quantity, comment, SwapDirection.BUY);
        }

        return commentIdentifier;
    }

    bytes32 constant PERMIT_BUY_ON_SECONDARY_AND_COMMENT_DOMAIN =
        keccak256(
            "PermitBuyOnSecondaryAndComment(address commenter,uint256 quantity,address collection,uint256 tokenId,uint256 maxEthToSpend,uint160 sqrtPriceLimitX96,string comment,uint256 deadline,bytes32 nonce,uint32 sourceChainId,uint32 destinationChainId)"
        );

    function _hashPermitBuyOnSecondaryAndComment(PermitBuyOnSecondaryAndComment memory permit) internal pure returns (bytes memory) {
        return
            abi.encode(
                PERMIT_BUY_ON_SECONDARY_AND_COMMENT_DOMAIN,
                permit.commenter,
                permit.quantity,
                permit.collection,
                permit.tokenId,
                permit.maxEthToSpend,
                permit.sqrtPriceLimitX96,
                keccak256(bytes(permit.comment)),
                permit.deadline,
                permit.nonce,
                permit.sourceChainId,
                permit.destinationChainId
            );
    }

    /// @notice Hashes the permit data for a buy on secondary and comment operation
    /// @param permit The PermitBuyOnSecondaryAndComment struct containing the permit data
    /// @return bytes32 The hash of the permit data for signing
    function hashPermitBuyOnSecondaryAndComment(PermitBuyOnSecondaryAndComment memory permit) public view returns (bytes32) {
        return _hashTypedDataV4(keccak256(_hashPermitBuyOnSecondaryAndComment(permit)), permit.sourceChainId);
    }

    /// @notice Buys tokens on secondary market and adds a comment, without needing to pay a spark for the comment. Attributes the
    /// comment to the signer of the message. Meant to be used for cross-chain commenting where a permit is used.
    /// @dev The signer must match the commenter field in the permit.
    /// @param permit The PermitBuyOnSecondaryAndComment struct containing the permit data
    /// @param signature The signature of the permit
    /// @return The identifier of the newly created comment
    function permitBuyOnSecondaryAndComment(
        PermitBuyOnSecondaryAndComment calldata permit,
        bytes calldata signature
    ) public payable returns (IComments.CommentIdentifier memory) {
        bytes32 digest = hashPermitBuyOnSecondaryAndComment(permit);

        _validateAndUsePermit(digest, permit.nonce, signature, permit.commenter, permit.deadline, permit.destinationChainId);

        return
            _buyOnSecondaryAndComment(
                permit.commenter,
                permit.quantity,
                permit.collection,
                permit.tokenId,
                payable(permit.commenter),
                permit.maxEthToSpend,
                permit.sqrtPriceLimitX96,
                permit.comment
            );
    }

    /// @notice Sells Zora 1155 tokens on secondary market and adds a comment.
    /// @dev Must sent ETH value of one spark for the comment.  Commenter must have approved this contract to transfer the tokens
    /// on the 1155 contract.
    /// @param commenter The address of the commenter. Must match the msg.sender. Commenter will be the seller of the tokens.
    /// @param quantity The number of tokens to sell
    /// @param collection The address of the 1155 collection
    /// @param tokenId The 1155 token Id to sell
    /// @param recipient The address to receive the ETH proceeds
    /// @param minEthToAcquire The minimum amount of ETH to receive from the sale
    /// @param sqrtPriceLimitX96 The sqrt price limit for the swap
    /// @param comment The comment to be added
    /// @return commentIdentifier The identifier of the newly created comment
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
    ) external payable returns (IComments.CommentIdentifier memory commentIdentifier) {
        if (commenter != msg.sender) {
            revert CommenterMismatch(msg.sender, commenter);
        }

        if (bytes(comment).length == 0) {
            // if we are not sending a comment, we should not send any ETH
            if (msg.value != 0) {
                revert WrongValueSent(0, msg.value);
            }
        } else {
            // if we are sending a comment, we should be required to send one spark
            if (msg.value != sparkValue) {
                revert WrongValueSent(sparkValue, msg.value);
            }

            bytes32 commentId;
            // submit the comment, attaching the spark value if it is sent
            (commentIdentifier, commentId) = comments.delegateComment{value: msg.value}(
                commenter,
                collection,
                tokenId,
                comment,
                emptyReplyTo,
                address(0),
                address(0)
            );

            emit SwappedOnSecondaryAndCommented(commentId, commentIdentifier, quantity, comment, SwapDirection.SELL);
        }

        // wrapped around brackets to prevent stack too deep error
        {
            // transfer the tokens to the secondary swap
            IERC1155(collection).safeTransferFrom(
                // transferring from the commenter to the secondary swap contract.
                // commenter must have approved this contract to transfer tokens.
                address(commenter),
                address(secondarySwap),
                tokenId,
                quantity,
                abi.encode(recipient, minEthToAcquire, sqrtPriceLimitX96)
            );
        }

        return commentIdentifier;
    }

    /// @notice Returns the name of the contract
    /// @return The name of the contract
    function contractName() public pure returns (string memory) {
        return "Caller and Commenter";
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // check that new implementation's contract name matches the current contract name
        if (!Strings.equal(IHasContractName(newImplementation).contractName(), this.contractName())) {
            revert UpgradeToMismatchedContractName(this.contractName(), IHasContractName(newImplementation).contractName());
        }
    }

    function _equals(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(bytes(a)) == keccak256(bytes(b)));
    }
}
