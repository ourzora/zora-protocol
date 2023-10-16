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
import {ZoraCreator1155Attribution, ContractCreationConfig, PremintConfig, PremintConfigV2, TokenCreationConfig, TokenCreationConfigV2} from "./ZoraCreator1155Attribution.sol";

interface IZoraCreator1155PremintV1Signatures {
    function delegateSetupNewToken(PremintConfig calldata premintConfig, bytes calldata signature, address sender) external returns (uint256 newTokenId);
}

// interface for legacy v1 of premint executor methods
// maintained in order to not break existing calls
// to legacy api when this api is upgraded
interface ILegacyZoraCreator1155PremintExecutor {
    event Preminted(
        address indexed contractAddress,
        uint256 indexed tokenId,
        bool indexed createdNewContract,
        uint32 uid,
        ContractCreationConfig contractConfig,
        TokenCreationConfig tokenConfig,
        address minter,
        uint256 quantityMinted
    );

    function premint(
        ContractCreationConfig calldata contractConfig,
        PremintConfig calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        string calldata mintComment
    ) external payable returns (uint256 newTokenId);
}

/// @title Enables creation of and minting tokens on Zora1155 contracts transactions using eip-712 signatures.
/// Signature must provided by the contract creator, or an account that's permitted to create new tokens on the contract.
/// Mints the first x tokens to the executor of the transaction.
/// @author @oveddan
contract ZoraCreator1155PremintExecutorImpl is
    ILegacyZoraCreator1155PremintExecutor,
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

    event PremintedV2(
        address indexed contractAddress,
        uint256 indexed tokenId,
        bool indexed createdNewContract,
        uint32 uid,
        address minter,
        uint256 quantityMinted,
        bytes mintArgumets
    );

    /// Creates a new token on the given erc1155 contract on behalf of a creator, and mints x tokens to the executor of this transaction.
    /// If the erc1155 contract hasn't been created yet, it will be created with the given config within this same transaction.
    /// The creator must sign the intent to create the token, and must have mint new token permission on the erc1155 contract,
    /// or match the contract admin on the contract creation config if the contract hasn't been created yet.
    /// Contract address of the created contract is deterministically generated from the contract config and this contract's address.
    /// @param contractConfig Parameters for creating a new contract, if one doesn't exist yet.  Used to resolve the deterministic contract address.
    /// @param premintConfig Parameters for creating the token, and minting the initial x tokens to the executor.
    /// @param signature Signature of the creator of the token, which must match the signer of the premint config, or have permission to create new tokens on the erc1155 contract if it's already been created
    /// @param quantityToMint How many tokens to mint to the executor of this transaction once the token is created
    /// @param mintArguments Abi encoded additional mint arguments: including mintComment and mintReferral
    function premint(
        ContractCreationConfig calldata contractConfig,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        bytes calldata mintArguments
    ) external payable returns (uint256 newTokenId) {
        // get or create the contract with the given params
        // contract address is deterministic.
        (IZoraCreator1155 tokenContract, bool isNewContract) = ZoraCreator1155PremintExecutorImplLib.getOrCreateContract(zora1155Factory, contractConfig);

        // pass the signature and the premint config to the token contract to create the token.
        // The token contract will verify the signature and that the signer has permission to create a new token.
        // and then create and setup the token using the given token config.
        newTokenId = tokenContract.delegateSetupNewToken(premintConfig, signature, msg.sender);

        _performMint(tokenContract, premintConfig.tokenConfig.fixedPriceMinter, newTokenId, quantityToMint, mintArguments);

        // emit Preminted event
        emit PremintedV2(address(tokenContract), newTokenId, isNewContract, premintConfig.uid, msg.sender, quantityToMint, mintArguments);
    }

    /// Creates a new token on the given erc1155 contract on behalf of a creator, and mints x tokens to the executor of this transaction.
    /// If the erc1155 contract hasn't been created yet, it will be created with the given config within this same transaction.
    /// The creator must sign the intent to create the token, and must have mint new token permission on the erc1155 contract,
    /// or match the contract admin on the contract creation config if the contract hasn't been created yet.
    /// Contract address of the created contract is deterministically generated from the contract config and this contract's address.
    /// @param contractConfig Parameters for creating a new contract, if one doesn't exist yet.  Used to resolve the deterministic contract address.
    /// @param premintConfig Parameters for creating the token, and minting the initial x tokens to the executor.
    /// @param signature Signature of the creator of the token, which must match the signer of the premint config, or have permission to create new tokens on the erc1155 contract if it's already been created
    /// @param quantityToMint How many tokens to mint to the executor of this transaction once the token is created
    /// @param mintArguments Abi encoded additional mint arguments: including mintComment and mintReferral
    function premint(
        ContractCreationConfig calldata contractConfig,
        PremintConfig calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        bytes memory mintArguments
    ) public payable returns (uint256 newTokenId) {
        // get or create the contract with the given params
        // contract address is deterministic.
        (IZoraCreator1155 tokenContract, bool isNewContract) = ZoraCreator1155PremintExecutorImplLib.getOrCreateContract(zora1155Factory, contractConfig);

        // assume contract has legacy interface expecting v1 signatures; call it.
        newTokenId = IZoraCreator1155PremintV1Signatures(address(tokenContract)).delegateSetupNewToken(premintConfig, signature, msg.sender);

        _performMint(tokenContract, premintConfig.tokenConfig.fixedPriceMinter, newTokenId, quantityToMint, mintArguments);

        // emit Preminted event
        emit PremintedV2(address(tokenContract), newTokenId, isNewContract, premintConfig.uid, msg.sender, quantityToMint, mintArguments);
    }

    function _performMint(
        IZoraCreator1155 tokenContract,
        address fixedPriceMinter,
        uint256 tokenId,
        uint256 quantityToMint,
        bytes memory mintArguments
    ) internal {
        (address mintReferral, string memory mintComment) = ZoraCreator1155PremintExecutorImplLib.decodeMintArguments(mintArguments);

        if (quantityToMint != 0)
            // mint the number of specified tokens to the executor
            tokenContract.mintWithRewards{value: msg.value}(
                IMinter1155(fixedPriceMinter),
                tokenId,
                quantityToMint,
                abi.encode(msg.sender, mintComment),
                mintReferral
            );
    }

    function isValidSignature(
        address originalPremintCreator,
        address contractAddress,
        bytes32 hashedPremint,
        bytes32 signatureVersion,
        bytes calldata signature
    ) public view returns (bool isValid, address recoveredSigner) {
        return ZoraCreator1155Attribution.isValidSignature(originalPremintCreator, contractAddress, hashedPremint, signatureVersion, signature);
    }

    /// Gets the deterministic contract address for the given contract creation config.
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

    function isValidSignature(
        ContractCreationConfig calldata contractConfig,
        PremintConfig calldata premintConfig,
        bytes calldata signature
    ) public view returns (bool isValid, address contractAddress, address recoveredSigner) {
        contractAddress = getContractAddress(contractConfig);

        bytes32 hashedPremint = ZoraCreator1155Attribution.hashPremint(premintConfig);

        (isValid, recoveredSigner) = isValidSignature(
            contractConfig.contractAdmin,
            contractAddress,
            hashedPremint,
            ZoraCreator1155Attribution.HASHED_VERSION_1,
            signature
        );
    }

    function isValidSignature(
        ContractCreationConfig calldata contractConfig,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature
    ) public view returns (bool isValid, address contractAddress, address recoveredSigner) {
        contractAddress = getContractAddress(contractConfig);

        bytes32 hashedPremint = ZoraCreator1155Attribution.hashPremint(premintConfig);

        (isValid, recoveredSigner) = isValidSignature(
            contractConfig.contractAdmin,
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

    /// @notice Deprecated
    function premint(
        ContractCreationConfig calldata contractConfig,
        PremintConfig calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        string calldata mintComment
    ) external payable returns (uint256 newTokenId) {
        // encode legacy mint arguments to call current function:
        bytes memory mintArguments = ZoraCreator1155PremintExecutorImplLib.encodeMintArguments(address(0), mintComment);

        return premint(contractConfig, premintConfig, signature, quantityToMint, mintArguments);
    }
}
