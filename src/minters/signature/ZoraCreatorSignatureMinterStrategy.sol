// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Enjoy} from "_imagine/mint/Enjoy.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IMinter1155} from "../../interfaces/IMinter1155.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {SaleStrategy} from "../SaleStrategy.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {SaleCommandHelper} from "../utils/SaleCommandHelper.sol";
import {LimitedMintPerAddress} from "../utils/LimitedMintPerAddress.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IReadableAuthRegistry} from "../../interfaces/IAuthRegistry.sol";

/*


             ░░░░░░░░░░░░░░              
        ░░▒▒░░░░░░░░░░░░░░░░░░░░        
      ░░▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░      
    ░░▒▒▒▒░░░░░░░░░░░░░░    ░░░░░░░░    
   ░▓▓▒▒▒▒░░░░░░░░░░░░        ░░░░░░░    
  ░▓▓▓▒▒▒▒░░░░░░░░░░░░        ░░░░░░░░  
  ░▓▓▓▒▒▒▒░░░░░░░░░░░░░░    ░░░░░░░░░░  
  ░▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░  
  ░▓▓▓▓▓▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░  
   ░▓▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░  
    ░░▓▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░    
    ░░▓▓▓▓▓▓▒▒▒▒▒▒▒▒░░░░░░░░░▒▒▒▒▒░░    
      ░░▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░      
          ░░▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░░          

               OURS TRULY,


    github.com/ourzora/zora-1155-contracts

 */

/// @title ZoraCreatorSignatureMinterStrategy
/// @notice Mints tokens based on signature created by an authorized signer
/// @author @oveddan
contract ZoraCreatorSignatureMinterStrategy is Enjoy, SaleStrategy, LimitedMintPerAddress, EIP712 {
    using SaleCommandHelper for ICreatorCommands.CommandSet;

    /// @notice General signatue sale settings
    struct SalesConfig {
        /// @notice Registry that decides which account is authorized to sign signatures
        /// to mint for the sale
        IReadableAuthRegistry authorizedSignatureCreators;
    }

    // target -> settings
    mapping(address => SalesConfig) signatureSaleSettings;
    // target contract -> unique nonce -> if has been minted already
    mapping(address => mapping(bytes32 => bool)) private minted;

    /// @notice Event for sale configuration updated
    event SaleSet(address indexed mediaContract, SalesConfig signatureSaleSettings);

    error SaleEnded();
    error SaleHasNotStarted();
    error WrongValueSent(uint256 expectedValue, uint256 valueSent);
    error InvalidSignature();
    error AlreadyMinted();
    error MissingFundsRecipient();
    error Expired(uint256 expiration);

    bytes32 constant REQUEST_MINT_TYPEHASH =
        keccak256(
            "requestMint(address target,uint256 tokenId,bytes32 nonce,uint256 quantity,uint256 pricePerToken,uint256 expiration,address mintTo,address fundsRecipient)"
        );

    /// @notice ContractURI for contract information with the strategy
    function contractURI() external pure override returns (string memory) {
        return "https://github.com/ourzora/zora-1155-contracts/";
    }

    /// @notice The name of the sale strategy
    function contractName() external pure override returns (string memory) {
        return "Signature Sale Strategy";
    }

    /// @notice The version of the sale strategy
    function contractVersion() external pure override returns (string memory) {
        return "1.0.0";
    }

    constructor() EIP712("ZoraSignatureMinterStrategy", "1") {}

    struct MintRequestCallData {
        /// @param nonce Unique id of the mint included in the signature
        bytes32 nonce;
        /// @param pricePerToken Price per token
        uint256 pricePerToken;
        /// @param expiration When signature expires
        uint256 expiration;
        /// @param mintTo Which account should receive the mint
        address mintTo;
        address fundsRecipient;
        /// @param signature The signature created by the authorized signer
        bytes signature;
    }

    /// @notice Compiles and returns the commands needed to mint a token using this sales strategy.  Requires a signature
    /// to have been created off-chain by an authorized signer.
    /// @param tokenId The token ID to mint
    /// @param quantity The quantity of tokens to mint
    /// @param ethValueSent The amount of ETH sent with the transaction
    /// @param minterArguments The additional arguments passed to the minter encoded as calldata.  This should include: nonce (randomly generated unique id), pricePerToken (amount needed to pay per token), expiration (signature expiration), mintTo (which account will receive the mint), and the signature.
    function requestMint(
        address,
        uint256 tokenId,
        uint256 quantity,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external returns (ICreatorCommands.CommandSet memory) {
        address target = msg.sender;
        // these arguments are what don't fit into the standard requestMint Args
        MintRequestCallData memory mintRequestCalldata = abi.decode(minterArguments, (MintRequestCallData));

        address signer = recoverSignature(
            target,
            tokenId,
            mintRequestCalldata.nonce,
            quantity,
            mintRequestCalldata.pricePerToken,
            mintRequestCalldata.expiration,
            mintRequestCalldata.mintTo,
            mintRequestCalldata.fundsRecipient,
            mintRequestCalldata.signature
        );

        if (signer == address(0) || !isAuthorizedToSign(signer, target)) {
            revert InvalidSignature();
        }

        if (minted[target][mintRequestCalldata.nonce]) {
            revert AlreadyMinted();
        }
        minted[target][mintRequestCalldata.nonce] = true;

        // validate that the mint hasn't expired
        if (block.timestamp > mintRequestCalldata.expiration) {
            revert Expired(mintRequestCalldata.expiration);
        }

        // validate that proper value was sent
        if (quantity * mintRequestCalldata.pricePerToken != ethValueSent) {
            revert WrongValueSent(quantity * mintRequestCalldata.pricePerToken, ethValueSent);
        }

        return _executeMintAndTransferFunds(tokenId, quantity, mintRequestCalldata.mintTo, ethValueSent, mintRequestCalldata.fundsRecipient);
    }

    /// Helper utility to encode additional arguments needed to send to mint
    function encodeMinterArguments(MintRequestCallData calldata mintRequestCalldata) external pure returns (bytes memory) {
        return abi.encode(mintRequestCalldata);
    }

    /// Used to create a hash of the data for the requestMint function,
    /// that is to be signed by the authorized signer.
    function delegateCreateContractHashTypeData(
        address target,
        uint256 tokenId,
        bytes32 nonce,
        uint256 quantity,
        uint256 pricePerToken,
        uint256 expiration,
        address mintTo,
        address fundsRecipient
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(REQUEST_MINT_TYPEHASH, target, tokenId, nonce, quantity, pricePerToken, expiration, mintTo, fundsRecipient));

        return _hashTypedDataV4(structHash);
    }

    function recoverSignature(
        address target,
        uint256 tokenId,
        bytes32 nonce,
        uint256 quantity,
        uint256 pricePerToken,
        uint256 expiration,
        address mintTo,
        address fundsRecipient,
        bytes memory signature
    ) public view returns (address) {
        bytes32 digest = delegateCreateContractHashTypeData(target, tokenId, nonce, quantity, pricePerToken, expiration, mintTo, fundsRecipient);

        return ECDSA.recover(digest, signature);
    }

    function isAuthorizedToSign(address signer, address target) public view returns (bool) {
        return signatureSaleSettings[target].authorizedSignatureCreators.isAuthorized(signer);
    }

    function _executeMintAndTransferFunds(
        uint256 tokenId,
        uint256 quantity,
        address mintTo,
        uint256 ethValueSent,
        address fundsRecipient
    ) private pure returns (ICreatorCommands.CommandSet memory commands) {
        // Should transfer funds if funds recipient is set to a non-default address
        bool shouldTransferFunds = ethValueSent > 0;

        // Setup contract commands
        commands.setSize(shouldTransferFunds ? 2 : 1);
        // Mint command
        commands.mint(mintTo, tokenId, quantity);

        // If we have a non-default funds recipient for this token
        if (shouldTransferFunds) {
            if (fundsRecipient == address(0)) revert MissingFundsRecipient();
            commands.transfer(fundsRecipient, ethValueSent);
        }
    }

    /// @notice Sets the sale configuration for a token.  Meant to be called from the erc1155 contract
    function setSale(SalesConfig calldata _signatureSaleSettings) external {
        signatureSaleSettings[msg.sender] = _signatureSaleSettings;

        // Emit event for new sale
        emit SaleSet(msg.sender, _signatureSaleSettings);
    }

    /// @notice Resets the sale configuration for a token
    function resetSale(uint256 tokenId) external override {
        delete signatureSaleSettings[msg.sender];

        // Emit event with empty sale
        emit SaleSet(msg.sender, signatureSaleSettings[msg.sender]);
    }

    /// @notice Gets the sale configuration for a token
    /// @param tokenContract address to look up sale for
    function sale(address tokenContract) external view returns (SalesConfig memory) {
        return signatureSaleSettings[tokenContract];
    }

    /// @notice IERC165 interface
    /// @param interfaceId intrfaceinterface id to match
    function supportsInterface(bytes4 interfaceId) public pure virtual override(LimitedMintPerAddress, SaleStrategy) returns (bool) {
        return super.supportsInterface(interfaceId) || LimitedMintPerAddress.supportsInterface(interfaceId) || SaleStrategy.supportsInterface(interfaceId);
    }
}
