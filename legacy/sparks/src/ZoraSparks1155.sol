// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IZoraSparks1155, IUpdateableTokenURI} from "./interfaces/IZoraSparks1155.sol";
import {IZoraSparksURIManager} from "./interfaces/IZoraSparksURIManager.sol";
import {IERC7572} from "./interfaces/IERC7275.sol";
import {SparksStorageBase} from "./SparksStorageBase.sol";
import {TokenConfig, Redemption} from "./ZoraSparksTypes.sol";
import {ILegacyNaming} from "@zoralabs/shared-contracts/interfaces/ILegacyNaming.sol";
import {IZoraCreator1155PremintExecutorV2} from "@zoralabs/shared-contracts/interfaces/IZoraCreator1155PremintExecutorV2.sol";
import {ContractCreationConfig, PremintConfigV2, MintArguments, PremintResult} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {PremintEncoding} from "@zoralabs/shared-contracts/premint/PremintEncoding.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {TransferHelperUtils} from "./utils/TransferHelperUtils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {Arrays} from "@openzeppelin/contracts/utils/Arrays.sol";
import {IZoraSparks1155Managed} from "./interfaces/IZoraSparks1155Managed.sol";
import {UnorderedNonces} from "./utils/UnorderedNonces.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {IRedeemHandler} from "./interfaces/IRedeemHandler.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Zora SPARKs 1155
/// @dev The Zora SPARKs 1155 contract is an implementation of the ERC1155 standard with additional features:
///
/// Each token id has an associated backing value, either in ETH value or an ERC20 token value.
/// Accounts can mint tokens by transferring the value per token * quantity to the contract based on the token's
/// price per token and the backing value type.
/// The price of each token cannot be changed, ensuring that the value of each token is fixed, and the equivalent
/// value can be redeemed.
///
/// Accounts can redeem tokens by burning them and having their equivalent value in ETH or underlying ERC20 transferred
/// to a desired recipient.  The amount of value redeemed is based on the quantity of tokens burned * the price per token.
///
/// Administrative actions, such as creating tokens, can only be performed by addresses authorized by the authority contract.
/// Additionally SPARKs can only be minted by addresses authorized by that authority contract.
/// Actions involving access to owned SPARKs, such as redeeming, can only be performed by the owner of the SPARKs, or
/// by using a permit based signature signed by the owner of the SPARKs.
/// @author oveddan
contract ZoraSparks1155 is
    ERC1155,
    IERC7572,
    AccessManaged,
    IZoraSparks1155,
    IZoraSparks1155Managed,
    IUpdateableTokenURI,
    ILegacyNaming,
    SparksStorageBase,
    EIP712,
    UnorderedNonces
{
    using SafeERC20 for IERC20;
    uint256 public constant MINIMUM_ETH_PRICE = 0.000000001 ether;
    uint256 public constant MINIMUM_ERC20_PRICE = 10_000;
    address public constant ETH_ADDRESS = address(0);

    string public constant NAME = "Sparks";
    string public constant VERSION = "1";

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address to,uint256[] tokenIds,uint256[] quantities,bytes safeTransferData,uint256 nonce,uint256 deadline)");

    bytes32 private constant PERMIT_TRANSFER_SINGLE =
        keccak256("PermitSafeTransfer(address owner,address to,uint256 tokenId,uint256 quantity,bytes safeTransferData,uint256 nonce,uint256 deadline)");

    constructor() ERC1155("") AccessManaged(msg.sender) EIP712(NAME, VERSION) {}

    /// @notice Creates a new token with a specified price and token address.
    /// @dev Can only be called by an address authorized by the authority contract.
    /// If a token has already been created with this id, it will revert.
    /// @param tokenId id of token to create
    /// @param tokenConfig Configuratino of the token, including price per token and address.
    function createToken(uint256 tokenId, TokenConfig calldata tokenConfig) public override restricted {
        _createToken(tokenId, tokenConfig);
    }

    function _createToken(uint256 tokenId, TokenConfig memory tokenConfig) private {
        if (tokenConfigs[tokenId].price > 0) {
            revert TokenAlreadyCreated();
        }
        uint256 minimumPrice = tokenConfig.tokenAddress == ETH_ADDRESS ? MINIMUM_ETH_PRICE : MINIMUM_ERC20_PRICE;
        if (tokenConfig.price < minimumPrice) {
            revert InvalidTokenPrice();
        }
        if (tokenConfig.redeemHandler != address(0) && !IERC165(tokenConfig.redeemHandler).supportsInterface(type(IRedeemHandler).interfaceId)) {
            // validate that the configured redeemHandler is an actual IRedeemHandler by checking
            // if it supports the IRedeemHandler interface.
            revert NotARedeemHandler(tokenConfig.redeemHandler);
        }

        emit TokenCreated(tokenId, tokenConfig.price, tokenConfig.tokenAddress);

        tokenConfigs[tokenId] = tokenConfig;
    }

    /// @notice Sparks a specified quantity of tokens to the recipient by sending ETH to the contract.
    /// The value of the ETH sent must be equal to the price of the token to mint * quantity.
    /// @dev Can only be called by the an address authorized by the authority contract.
    /// @param tokenId The ID of the token to mint
    /// @param quantity The quantity of tokens to mint
    /// @param recipient The address to receive the minted tokens
    /// @param data Data to include in  the mint call, this will be passed through to IERC1155Receiver.onERC1155Received as the data argument
    function mintTokenWithEth(uint256 tokenId, uint256 quantity, address recipient, bytes memory data) public payable restricted {
        _mintWithEth(tokenId, quantity, recipient, data);
    }

    function _mintWithEth(uint256 tokenId, uint256 quantity, address recipient, bytes memory data) private {
        uint256 _tokenPrice = _validateTokenAndGetPrice(tokenId, ETH_ADDRESS);

        uint256 totalMintPrice = _tokenPrice * quantity;

        if (msg.value != totalMintPrice) {
            revert IncorrectAmountSent();
        }

        _mint(recipient, tokenId, quantity, data);
    }

    /// @notice Sparks a specified quantity of tokens to the recipient by transferring ERC20 tokens to the contract.
    /// The value of the tokens transferred must be equal to the price of the token to mint * quantity.
    /// The token at the token id must have the same address as the `tokenAddress` parameter.
    /// @dev Can only be called by the a contract authorized by the authority contract.
    /// @param tokenId The ID of the token to mint
    /// @param tokenAddress The address of the ERC20 token to use for minting
    /// @param quantity The quantity of tokens to mint
    /// @param recipient The address to receive the minted SPARKs
    /// @param data Data to include in  the mint call, this will be passed through to IERC1155Receiver.onERC1155Received as the data argument
    function mintTokenWithERC20(uint256 tokenId, address tokenAddress, uint quantity, address recipient, bytes memory data) external restricted {
        _mintWithERC20(tokenId, quantity, recipient, tokenAddress, data);
    }

    function _mintWithERC20(uint256 tokenId, uint256 quantity, address recipient, address tokenAddress, bytes memory data) private {
        uint256 _tokenPrice = _validateTokenAndGetPrice(tokenId, tokenAddress);

        uint256 totalMintPrice = _tokenPrice * quantity;

        uint256 beforeBalance = IERC20(tokenAddress).balanceOf(address(this));

        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), totalMintPrice);

        uint256 afterBalance = IERC20(tokenAddress).balanceOf(address(this));

        if ((beforeBalance + totalMintPrice) != afterBalance) {
            revert ERC20TransferSlippage();
        }

        _mint(recipient, tokenId, quantity, data);
    }

    /// To follow the EIP-7572 standard, emits an event when the URI is updated so that indexers
    /// can pick up the new URI.
    function notifyURIsUpdated(string calldata newContractURI, string calldata newBaseURI) external restricted {
        emit URIsUpdated(newContractURI, newBaseURI);
        emit ContractURIUpdated();
    }

    /// Emits an event when the URI is updated so that indexers can pick up the new URI.
    function notifyUpdatedTokenURI(string calldata newUri, uint256 tokenId) external restricted {
        emit URI(newUri, tokenId);
    }

    /// Gets the contract URI
    /// @dev Pulls this dynamically from the manager.
    function contractURI() external view returns (string memory) {
        return IZoraSparksURIManager(authority()).contractURI();
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        if (!tokenExists(tokenId)) {
            revert NoUriForNonexistentToken();
        }
        return IZoraSparksURIManager(authority()).uri(tokenId);
    }

    function _validateTokenAndGetPrice(uint256 tokenId, address tokenAddress) private view returns (uint256 pricePerToken) {
        TokenConfig storage tokenConfig = tokenConfigs[tokenId];
        // validate that the token has been created
        if (tokenConfig.price == 0) {
            revert TokenDoesNotExist();
        }
        // validate that the token address matches the expected address
        if (tokenConfig.tokenAddress != tokenAddress) {
            revert TokenMismatch(tokenConfig.tokenAddress, tokenAddress);
        }

        pricePerToken = tokenConfig.price;
    }

    /// @notice Redeems the equivalent value of a specified quantity of tokens and sends it to the recipient.
    /// @dev This function can only be called by the current owner of the SPARKs. It burns the SPARKs,
    /// and transfers the underlying value to the recipient.
    /// @param tokenId The ID of the SPARK to redeem
    /// @param quantity The quantity of SPARKs to redeem
    /// @param recipient The address to have the value transferred to
    /// @return The token address (0 if eth) and value redeemed
    function redeem(uint256 tokenId, uint256 quantity, address recipient) external override returns (Redemption memory) {
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }

        _burn(msg.sender, tokenId, quantity);

        return _transferBackingBalanceToRecipient(tokenId, quantity, recipient);
    }

    /// @notice Redeems the equivalent value of a specified quantity of token ids and corresponding quantities and
    /// sends the values to the recipient.
    /// @dev This function can only be called by the current owner of the SPARKs. It burns the SPARKs,
    /// @param tokenIds Ids of the tokens to redeem
    /// @param quantities Quantities of the tokens to redeem
    /// @param recipient Account to receive the underlying value
    /// @return redemptions An array of redemptions, each containing the token address (0 if eth) and value redeemed
    function redeemBatch(
        uint256[] calldata tokenIds,
        uint256[] calldata quantities,
        address recipient
    ) external override returns (Redemption[] memory redemptions) {
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }
        if (tokenIds.length != quantities.length) {
            revert ArrayLengthMismatch(tokenIds.length, quantities.length);
        }

        _burnBatch(msg.sender, tokenIds, quantities);

        redemptions = new Redemption[](tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            redemptions[i] = _transferBackingBalanceToRecipient(tokenIds[i], quantities[i], recipient);
        }
    }

    function _transferBackingBalanceToRecipient(uint256 tokenId, uint256 quantity, address recipient) private returns (Redemption memory) {
        TokenConfig storage tokenConfig = tokenConfigs[tokenId];

        uint256 valueRedeemed = tokenConfig.price * quantity;
        address tokenAddress = tokenConfig.tokenAddress;
        address redeemHandler = tokenConfig.redeemHandler;

        if (tokenAddress == ETH_ADDRESS) {
            _redeemEth(redeemHandler, recipient, tokenId, quantity, valueRedeemed);
        } else {
            _redeemErc20(tokenAddress, redeemHandler, recipient, tokenId, quantity, valueRedeemed);
        }

        return Redemption({tokenAddress: tokenAddress, valueRedeemed: valueRedeemed});
    }

    function _redeemEth(address redeemHandler, address recipient, uint256 tokenId, uint256 quantity, uint256 valueRedeemed) private {
        if (redeemHandler == address(0)) {
            TransferHelperUtils.safeSendETH(recipient, valueRedeemed);
        } else {
            // if there is a redeem handler, transfer the eth value redeemed to it
            // by calling handleRedeemEth on it with the valueRedeemed as payable value.
            // It will handle what to do with the eth value, such as forwarding
            // it to the desired recipient.
            IRedeemHandler(redeemHandler).handleRedeemEth{value: valueRedeemed}(msg.sender, tokenId, quantity, recipient);
        }
    }

    function _redeemErc20(address tokenAddress, address redeemHandler, address recipient, uint256 tokenId, uint256 quantity, uint256 valueRedeemed) private {
        IERC20 erc20Contract = IERC20(tokenAddress);
        if (redeemHandler == address(0)) {
            erc20Contract.safeTransfer(recipient, valueRedeemed);
        } else {
            // If there is a redeem handler, transfer the erc20 redeemed value redeemed to it
            // instead of directly to the recipient.
            // Call handleRedeemErc20 which for which it can handle what to do with those erc20,
            // such as transferring them to the recipient.
            erc20Contract.safeTransfer(redeemHandler, valueRedeemed);
            IRedeemHandler(redeemHandler).handleRedeemErc20(valueRedeemed, msg.sender, tokenId, quantity, recipient);
        }
    }

    /// If the token with this id exists
    /// @param tokenId Id of token to check
    function tokenExists(uint256 tokenId) public view override returns (bool) {
        return tokenPrice(tokenId) > 0;
    }

    /// Gets the price of the token in the backing value
    /// @param tokenId Id of the token to get the price of
    function tokenPrice(uint256 tokenId) public view override returns (uint256) {
        return uint256(tokenConfigs[tokenId].price);
    }

    function name() external pure override returns (string memory) {
        return "Zora Sparks";
    }

    function symbol() external pure override returns (string memory) {
        return "SPARK";
    }

    function getTokenConfig(uint256 tokenId) external view returns (TokenConfig memory) {
        return tokenConfigs[tokenId];
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) public override(ERC1155, IERC1155) {
        // if there is data, emit the transfer event that includes data
        _emitTransferBatchWithDataIfData(from, to, ids, values, data);

        super.safeBatchTransferFrom(from, to, ids, values, data);
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory data) public override(ERC1155, IERC1155) {
        // if there is data, emit the transfer event that includes data
        _emitTransferSingleIfData(from, to, id, value, data);

        super.safeTransferFrom(from, to, id, value, data);
    }

    /// Allows an account to execute a transaction on the behalf of another account or contract that holds SPARKs.
    /// This transaction behaves like a transferBatchToManagerAndCall, but a permit signature is used to authorize the transaction, and
    /// instead of transferring the msg.sender's SPARKs, the signer's SPARKs are transferred. Works with both EOA and contract based signatures.
    /// @param permit Parameters of the permit, including the owner, tokenIds, quantities, safeTransferData, call, nonce, and deadline
    /// @param signature Signature of the permit.  Signature must have been signed by address of the owner field.
    /// @dev Unlike transferBatchToManagerAndCall, payable value cannot be forwarded to the manager.
    function permitSafeTransferBatch(PermitBatch calldata permit, bytes calldata signature) external {
        // ensure the permit's deadline has not passed
        if (block.timestamp > permit.deadline) {
            revert ERC2612ExpiredSignature(block.timestamp);
        }

        // check and use nonce
        _useCheckedNonce(permit.owner, permit.nonce);

        // get digest of the permit
        bytes32 digest = hashPermitBatch(permit);

        // validate the signature.  If owner is a contract, the signature is validated against that contract using ERC-1271
        _validateSignerIsOwner(digest, signature, permit.owner);

        // if there is data, emit the transfer event that includes data
        _emitTransferBatchWithDataIfData(permit.owner, permit.to, permit.tokenIds, permit.quantities, permit.safeTransferData);

        // transfer the SPARKs to the manager
        _safeBatchTransferFrom(permit.owner, permit.to, permit.tokenIds, permit.quantities, permit.safeTransferData);
    }

    /// Hashes a permit in the to create a digest that is to be signed.
    /// @param permit the permit to hash
    function hashPermitSingle(PermitSingle calldata permit) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TRANSFER_SINGLE,
                permit.owner,
                permit.to,
                permit.tokenId,
                permit.quantity,
                keccak256(permit.safeTransferData),
                permit.nonce,
                permit.deadline
            )
        );

        return _hashTypedDataV4(structHash);
    }

    /// Hashes a permit in the to create a digest that is to be signed.
    /// @param permit the permit to hash
    function hashPermitBatch(PermitBatch calldata permit) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                permit.owner,
                permit.to,
                keccak256(abi.encodePacked(permit.tokenIds)),
                keccak256(abi.encodePacked(permit.quantities)),
                keccak256(permit.safeTransferData),
                permit.nonce,
                permit.deadline
            )
        );

        return _hashTypedDataV4(structHash);
    }

    /// Allows an account to execute a transaction on the behalf of another account or contract that holds SPARKs.
    /// This transaction behaves like a transferBatchToManagerAndCall, but a permit signature is used to authorize the transaction, and
    /// instead of transferring the msg.sender's SPARKs, the signer's SPARKs are transferred. Works with both EOA and contract based signatures.
    /// @param permit Parameters of the permit, including the owner, tokenIds, quantities, safeTransferData, call, nonce, and deadline
    /// @param signature Signature of the permit.  Signature must have been signed by address of the owner field.
    /// @dev Unlike transferBatchToManagerAndCall, payable value cannot be forwarded to the manager.
    function permitSafeTransfer(PermitSingle calldata permit, bytes calldata signature) external {
        // ensure the permit's deadline has not passed
        if (block.timestamp > permit.deadline) {
            revert ERC2612ExpiredSignature(block.timestamp);
        }

        // check and use nonce
        _useCheckedNonce(permit.owner, permit.nonce);

        // get digest of the permit
        bytes32 digest = hashPermitSingle(permit);

        // validate the signature.  If owner is a contract, the signature is validated against that contract using ERC-1271
        _validateSignerIsOwner(digest, signature, permit.owner);

        // if there is data, emit the transfer event that includes data
        _emitTransferSingleIfData(permit.owner, permit.to, permit.tokenId, permit.quantity, permit.safeTransferData);

        // transfer the SPARKs to the manager
        _safeTransferFrom(permit.owner, permit.to, permit.tokenId, permit.quantity, permit.safeTransferData);
    }

    /// Debugging function used to validate a permit signature.  The signer must match the `owner` fields
    /// on the permit.  Works with both EOA and contract based signatures.
    /// @param permit the permit to validate
    /// @param signature the signature for the permit to validate
    /// @return true if the signature is valid, and signed by
    function isValidSignatureTransferSingle(PermitSingle calldata permit, bytes calldata signature) external view returns (bool) {
        bytes32 digest = hashPermitSingle(permit);

        return SignatureChecker.isValidSignatureNow(permit.owner, digest, signature);
    }

    /// Debugging function used to validate a permit signature.  The signer must match the `owner` fields
    /// on the permit.  Works with both EOA and contract based signatures.
    /// @param permit the permit to validate
    /// @param signature the signature for the permit to validate
    /// @return true if the signature is valid, and signed by
    function isValidSignatureTransferBatch(PermitBatch calldata permit, bytes calldata signature) external view returns (bool) {
        bytes32 digest = hashPermitBatch(permit);

        return SignatureChecker.isValidSignatureNow(permit.owner, digest, signature);
    }

    function _emitTransferBatchWithDataIfData(address from, address to, uint256[] memory ids, uint256[] memory values, bytes memory data) private {
        if (data.length > 0) {
            emit TransferBatchWithData(from, to, ids, values, data);
        }
    }

    function _emitTransferSingleIfData(address from, address to, uint256 id, uint256 value, bytes memory data) private {
        if (data.length > 0) {
            emit TransferSingleWithData(from, to, id, value, data);
        }
    }

    function _validateSignerIsOwner(bytes32 digest, bytes calldata signature, address owner) private view {
        // Checks if a signature is valid for a given signer and data hash. If the signer is a smart contract, the
        // signature is validated against that smart contract using ERC-1271, otherwise it's validated using `ECDSA.recover`
        bool _isValidSignature = SignatureChecker.isValidSignatureNow(owner, digest, signature);

        if (!_isValidSignature) {
            revert InvalidSignature();
        }
    }

    /// Auto-incrementing nonces for each account when creating a permit based signature. This nonce is incremented
    /// when a permit for a user is used onchain.
    /// @param owner to get the nonce of.
    function nonceUsed(address owner, uint256 nonce) public view virtual override(IZoraSparks1155Managed, UnorderedNonces) returns (bool) {
        return super.nonceUsed(owner, nonce);
    }

    /// Handles keeping track of the overall user balance
    /// @param from Transfer user from
    /// @param to Transfer user to
    /// @param ids List of IDs being transferred
    /// @param values List of values being transferred (zipped array alongside ids)
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal virtual override {
        // Do the update
        super._update(from, to, ids, values);

        // Track the update
        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 value = Arrays.unsafeMemoryAccess(values, i);
            if (from != address(0)) {
                accountBalances[from] -= value;
            }
            if (to != address(0)) {
                accountBalances[to] += value;
            }
        }
    }

    /// @notice Get the user sparks balance onchain
    /// @param account account to get balance for
    /// @return the entire user balance across all token IDs
    function balanceOfAccount(address account) external view returns (uint256) {
        return accountBalances[account];
    }
}
