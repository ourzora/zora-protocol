// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {UUPSUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "../utils/ownable/Ownable2StepUpgradeable.sol";
import {IHasContractName} from "../interfaces/IContractMetadata.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155Errors} from "../interfaces/IZoraCreator1155Errors.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {SharedBaseConstants} from "../shared/SharedBaseConstants.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {ERC1155DelegationStorageV1} from "../delegation/ERC1155DelegationStorageV1.sol";
import {ZoraCreator1155PremintExecutorImplLib} from "./ZoraCreator1155PremintExecutorImplLib.sol";
import {PremintEncoding, ZoraCreator1155Attribution, ContractCreationConfig, PremintConfig, PremintConfigV2, TokenCreationConfig, TokenCreationConfigV2} from "./ZoraCreator1155Attribution.sol";
import {IZoraCreator1155PremintExecutor, ILegacyZoraCreator1155PremintExecutor} from "../interfaces/IZoraCreator1155PremintExecutor.sol";

struct MintArguments {
    // which account should receive the tokens minted.  If set to address(0), then defaults to the msg.sender
    address mintRecipient;
    // comment to add to the mint
    string mintComment;
    // account that referred the minter to mint the tokens, this account will receive a mint referral award.  If set to address(0), no account will get the mint referral reward
    address mintReferral;
}

/// @title Enables creation of and minting tokens on Zora1155 contracts transactions using eip-712 signatures.
/// Signature must provided by the contract creator, or an account that's permitted to create new tokens on the contract.
/// Mints the first x tokens to the executor of the transaction.
/// @author @oveddan
contract ZoraCreator1155PremintExecutorImpl is
    ILegacyZoraCreator1155PremintExecutor,
    IZoraCreator1155PremintExecutor,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    IHasContractName,
    IZoraCreator1155Errors
{
    IZoraCreator1155Factory public immutable zora1155Factory;

    constructor(IZoraCreator1155Factory _factory) {
        zora1155Factory = _factory;
    }

    function initialize(address _initialOwner) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();
    }

    /// @notice Creates a new token on the given erc1155 contract on behalf of a creator, and mints x tokens to the executor of this transaction.
    /// If the erc1155 contract hasn't been created yet, it will be created with the given config within this same transaction.
    /// The creator must sign the intent to create the token, and must have mint new token permission on the erc1155 contract,
    /// or match the contract admin on the contract creation config if the contract hasn't been created yet.
    /// Contract address of the created contract is deterministically generated from the contract config and this contract's address.
    /// @dev For use with v2 of premint config, PremintConfigV2, which supports setting `createReferral`.
    /// @param contractConfig Parameters for creating a new contract, if one doesn't exist yet.  Used to resolve the deterministic contract address.
    /// @param premintConfig Parameters for creating the token, and minting the initial x tokens to the executor.
    /// @param signature Signature of the creator of the token, which must match the signer of the premint config, or have permission to create new tokens on the erc1155 contract if it's already been created
    /// @param quantityToMint How many tokens to mint to the mintRecipient
    /// @param mintArguments mint arguments specifying the token mint recipient, mint comment, and mint referral
    function premintV2(
        ContractCreationConfig calldata contractConfig,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        MintArguments calldata mintArguments
    ) external payable returns (PremintResult memory result) {
        (bytes memory encodedPremint, bytes32 premintVersion) = PremintEncoding.encodePremintV2(premintConfig);
        address fixedPriceMinter = premintConfig.tokenConfig.fixedPriceMinter;
        uint32 uid = premintConfig.uid;

        // we wrap this here to get around stack too deep issues
        {
            result = ZoraCreator1155PremintExecutorImplLib.premint({
                zora1155Factory: zora1155Factory,
                contractConfig: contractConfig,
                encodedPremintConfig: encodedPremint,
                premintVersion: premintVersion,
                signature: signature,
                quantityToMint: quantityToMint,
                fixedPriceMinter: fixedPriceMinter,
                mintArguments: mintArguments
            });
        }

        {
            emit PremintedV2({
                contractAddress: result.contractAddress,
                tokenId: result.tokenId,
                createdNewContract: result.createdNewContract,
                uid: uid,
                minter: msg.sender,
                quantityMinted: quantityToMint
            });
        }
    }

    /// Creates a new token on the given erc1155 contract on behalf of a creator, and mints x tokens to the executor of this transaction.
    /// If the erc1155 contract hasn't been created yet, it will be created with the given config within this same transaction.
    /// The creator must sign the intent to create the token, and must have mint new token permission on the erc1155 contract,
    /// or match the contract admin on the contract creation config if the contract hasn't been created yet.
    /// Contract address of the created contract is deterministically generated from the contract config and this contract's address.
    /// @dev For use with v1 of premint config, PremintConfigV2, which supports setting `createReferral`.
    /// @param contractConfig Parameters for creating a new contract, if one doesn't exist yet.  Used to resolve the deterministic contract address.
    /// @param premintConfig Parameters for creating the token, and minting the initial x tokens to the executor.
    /// @param signature Signature of the creator of the token, which must match the signer of the premint config, or have permission to create new tokens on the erc1155 contract if it's already been created
    /// @param quantityToMint How many tokens to mint to the mintRecipient
    /// @param mintArguments mint arguments specifying the token mint recipient, mint comment, and mint referral
    function premintV1(
        ContractCreationConfig calldata contractConfig,
        PremintConfig calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        MintArguments memory mintArguments
    ) public payable returns (PremintResult memory result) {
        (bytes memory encodedPremint, bytes32 premintVersion) = PremintEncoding.encodePremintV1(premintConfig);

        result = ZoraCreator1155PremintExecutorImplLib.premint({
            zora1155Factory: zora1155Factory,
            contractConfig: contractConfig,
            encodedPremintConfig: encodedPremint,
            premintVersion: premintVersion,
            signature: signature,
            quantityToMint: quantityToMint,
            fixedPriceMinter: premintConfig.tokenConfig.fixedPriceMinter,
            mintArguments: mintArguments
        });

        emit PremintedV2({
            contractAddress: result.contractAddress,
            tokenId: result.tokenId,
            createdNewContract: result.createdNewContract,
            uid: premintConfig.uid,
            minter: msg.sender,
            quantityMinted: quantityToMint
        });
    }

    /// @notice Gets the deterministic contract address for the given contract creation config.
    /// Contract address is generated deterministically from a hash based on the contract uri, contract name,
    /// contract admin, and the msg.sender, which is this contract's address.
    function getContractAddress(ContractCreationConfig calldata contractConfig) public view returns (address) {
        return ZoraCreator1155PremintExecutorImplLib.getContractAddress(zora1155Factory, contractConfig);
    }

    /// @notice Utility function to determine if a premint contract has been created for a uid of a premint, and if so,
    /// What is the token id that was created for the uid.
    function premintStatus(address contractAddress, uint32 uid) public view returns (bool contractCreated, uint256 tokenIdForPremint) {
        if (contractAddress.code.length == 0) {
            return (false, 0);
        }
        return (true, ERC1155DelegationStorageV1(contractAddress).delegatedTokenId(uid));
    }

    // @custom:deprecated use isValidSignatureV1 instead
    function isValidSignature(
        ContractCreationConfig calldata contractConfig,
        PremintConfig calldata premintConfig,
        bytes calldata signature
    ) public view returns (bool isValid, address contractAddress, address recoveredSigner) {
        contractAddress = getContractAddress(contractConfig);

        (isValid, recoveredSigner) = isValidSignatureV1(contractConfig.contractAdmin, contractAddress, premintConfig, signature);
    }

    /// @notice Recovers the signer of a premint, and checks if the signer is authorized to sign the premint.
    /// @dev for use with v1 of premint config, PremintConfig
    /// @param premintContractConfigContractAdmin If this contract was created via premint, the original contractConfig.contractAdmin.  Otherwise, set to address(0)
    /// @param contractAddress The determinstic 1155 contract address the premint is for
    /// @param premintConfig The premint config
    /// @param signature The signature of the premint
    /// @return isValid Whether the signature is valid
    /// @return recoveredSigner The signer of the premint
    function isValidSignatureV1(
        address premintContractConfigContractAdmin,
        address contractAddress,
        PremintConfig calldata premintConfig,
        bytes calldata signature
    ) public view returns (bool isValid, address recoveredSigner) {
        bytes32 hashedPremint = ZoraCreator1155Attribution.hashPremint(premintConfig);

        (isValid, recoveredSigner) = ZoraCreator1155Attribution.isValidSignature(
            premintContractConfigContractAdmin,
            contractAddress,
            hashedPremint,
            ZoraCreator1155Attribution.HASHED_VERSION_1,
            signature
        );
    }

    /// @notice Recovers the signer of a premint, and checks if the signer is authorized to sign the premint.
    /// @dev for use with v2 of premint config, PremintConfig
    /// @param premintContractConfigContractAdmin If this contract was created via premint, the original contractConfig.contractAdmin.  Otherwise, set to address(0)
    /// @param contractAddress The determinstic 1155 contract address the premint is for
    /// @param premintConfig The premint config
    /// @param signature The signature of the premint
    /// @return isValid Whether the signature is valid
    /// @return recoveredSigner The signer of the premint
    function isValidSignatureV2(
        address premintContractConfigContractAdmin,
        address contractAddress,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature
    ) public view returns (bool isValid, address recoveredSigner) {
        bytes32 hashedPremint = ZoraCreator1155Attribution.hashPremint(premintConfig);

        (isValid, recoveredSigner) = ZoraCreator1155Attribution.isValidSignature(
            premintContractConfigContractAdmin,
            contractAddress,
            hashedPremint,
            ZoraCreator1155Attribution.HASHED_VERSION_2,
            signature
        );
    }

    // upgrade related functionality

    /// @notice The name of the contract for upgrade purposes
    function contractName() external pure returns (string memory) {
        return "ZORA 1155 Premint Executor";
    }

    // upgrade functionality
    error UpgradeToMismatchedContractName(string expected, string actual);

    /// @notice Ensures the caller is authorized to upgrade the contract
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal override onlyOwner {
        if (!_equals(IHasContractName(_newImpl).contractName(), this.contractName())) {
            revert UpgradeToMismatchedContractName(this.contractName(), IHasContractName(_newImpl).contractName());
        }
    }

    function _equals(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(bytes(a)) == keccak256(bytes(b)));
    }

    // Deprecated functions:

    /// @custom:deprecated use premintV1 instead
    function premint(
        ContractCreationConfig calldata contractConfig,
        PremintConfig calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        string calldata mintComment
    ) external payable returns (uint256 newTokenId) {
        // encode legacy mint arguments to call current function:
        MintArguments memory mintArguments = MintArguments({mintRecipient: msg.sender, mintComment: mintComment, mintReferral: address(0)});

        return premintV1(contractConfig, premintConfig, signature, quantityToMint, mintArguments).tokenId;
    }
}
