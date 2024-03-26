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
import {ZoraCreator1155Attribution, DelegatedTokenCreation} from "./ZoraCreator1155Attribution.sol";
import {PremintEncoding, EncodedPremintConfig} from "@zoralabs/shared-contracts/premint/PremintEncoding.sol";
import {ContractCreationConfig, PremintConfig, PremintConfigV2, TokenCreationConfig, TokenCreationConfigV2, MintArguments, PremintResult, Erc20PremintConfigV1, Erc20TokenCreationConfigV1} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {ZoraCreator1155Attribution, DelegatedTokenCreation} from "./ZoraCreator1155Attribution.sol";
import {IZoraCreator1155PremintExecutor} from "../interfaces/IZoraCreator1155PremintExecutor.sol";
import {IZoraCreator1155DelegatedCreationLegacy, IHasSupportedPremintSignatureVersions} from "../interfaces/IZoraCreator1155DelegatedCreation.sol";
import {ZoraCreator1155FactoryImpl} from "../factory/ZoraCreator1155FactoryImpl.sol";
import {IRewardsErrors} from "@zoralabs/protocol-rewards/src/interfaces/IRewardsErrors.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/// @title Enables creation of and minting tokens on Zora1155 contracts transactions using eip-712 signatures.
/// Signature must provided by the contract creator, or an account that's permitted to create new tokens on the contract.
/// Mints the first x tokens to the executor of the transaction.
/// @author @oveddan
contract ZoraCreator1155PremintExecutorImpl is
    IZoraCreator1155PremintExecutor,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    IHasContractName,
    IZoraCreator1155Errors,
    IRewardsErrors
{
    IZoraCreator1155Factory public immutable zora1155Factory;

    constructor(IZoraCreator1155Factory _factory) {
        zora1155Factory = _factory;
        _disableInitializers();
    }

    function initialize(address _initialOwner) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();
    }

    /// @notice Executes the creation of an 1155 contract, token, and/or ERC20 sale signed by a creator, and mints the first tokens to the executor of this transaction.
    ///         To mint the first token(s) of an ERC20 sale, the executor must approve this contract the quantity * price of the mint.
    /// @dev For use with v3 of premint config, PremintConfig3, which supports ERC20 mints.
    /// @param contractConfig Parameters for creating a new contract, if one doesn't exist yet.  Used to resolve the deterministic contract address.
    /// @param premintConfig Parameters for creating the token, and minting the initial x tokens to the executor.
    /// @param signature Signature of the creator of the token, which must match the signer of the premint config, or have permission to create new tokens on the erc1155 contract if it's already been created
    /// @param quantityToMint How many tokens to mint to the mintRecipient
    /// @param mintArguments mint arguments specifying the token mint recipient, mint comment, and mint referral
    /// @param signerContract If a smart wallet was used to create the premint, the address of that smart wallet. Otherwise, set to address(0)
    function premintErc20V1(
        ContractCreationConfig calldata contractConfig,
        Erc20PremintConfigV1 calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        MintArguments calldata mintArguments,
        address firstMinter,
        address signerContract
    ) external returns (PremintResult memory result) {
        result = ZoraCreator1155PremintExecutorImplLib.getOrCreateContractAndToken(
            zora1155Factory,
            contractConfig,
            PremintEncoding.encodePremintErc20V1(premintConfig),
            signature,
            firstMinter,
            signerContract
        );

        if (quantityToMint > 0) {
            ZoraCreator1155PremintExecutorImplLib.performERC20Mint(
                premintConfig.tokenConfig.erc20Minter,
                premintConfig.tokenConfig.currency,
                premintConfig.tokenConfig.pricePerToken,
                quantityToMint,
                result,
                mintArguments
            );
        }

        {
            emit PremintedV2({
                contractAddress: result.contractAddress,
                tokenId: result.tokenId,
                createdNewContract: result.createdNewContract,
                uid: premintConfig.uid,
                minter: firstMinter,
                quantityMinted: quantityToMint
            });
        }
    }

    /// @notice Creates a new token on the given erc1155 contract on behalf of a creator, and mints x tokens to the executor of this transaction.
    /// For use for EIP-1271 based signatures, where there is a signer contract.
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
    /// @param signerContract If a smart wallet was used to create the premint, the address of that smart wallet. Otherwise, set to address(0)
    function premintV2WithSignerContract(
        ContractCreationConfig calldata contractConfig,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        MintArguments calldata mintArguments,
        address firstMinter,
        address signerContract
    ) public payable returns (PremintResult memory result) {
        result = ZoraCreator1155PremintExecutorImplLib.getOrCreateContractAndToken(
            zora1155Factory,
            contractConfig,
            PremintEncoding.encodePremintV2(premintConfig),
            signature,
            firstMinter,
            signerContract
        );

        if (quantityToMint > 0) {
            ZoraCreator1155PremintExecutorImplLib.mintWithEth(
                IZoraCreator1155(result.contractAddress),
                premintConfig.tokenConfig.fixedPriceMinter,
                result.tokenId,
                quantityToMint,
                mintArguments
            );
        }

        emit PremintedV2({
            contractAddress: result.contractAddress,
            tokenId: result.tokenId,
            createdNewContract: result.createdNewContract,
            uid: premintConfig.uid,
            minter: firstMinter,
            quantityMinted: quantityToMint
        });
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
        return premintV2WithSignerContract(contractConfig, premintConfig, signature, quantityToMint, mintArguments, msg.sender, address(0));
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
        MintArguments calldata mintArguments
    ) external payable returns (PremintResult memory result) {
        result = ZoraCreator1155PremintExecutorImplLib.getOrCreateContractAndToken(
            zora1155Factory,
            contractConfig,
            PremintEncoding.encodePremintV1(premintConfig),
            signature,
            msg.sender,
            address(0)
        );

        if (quantityToMint > 0) {
            ZoraCreator1155PremintExecutorImplLib.mintWithEth(
                IZoraCreator1155(result.contractAddress),
                premintConfig.tokenConfig.fixedPriceMinter,
                result.tokenId,
                quantityToMint,
                mintArguments
            );
        }

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
    function getContractAddress(ContractCreationConfig calldata contractConfig) public view override returns (address) {
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

    // @custom:deprecated use isAuthorizedToCreatePremint instead
    function isValidSignature(
        ContractCreationConfig calldata contractConfig,
        PremintConfig calldata premintConfig,
        bytes calldata signature
    ) public view returns (bool isValid, address contractAddress, address recoveredSigner) {
        contractAddress = getContractAddress(contractConfig);

        recoveredSigner = ZoraCreator1155Attribution.recoverSignerHashed(
            ZoraCreator1155Attribution.hashPremint(premintConfig),
            signature,
            contractAddress,
            PremintEncoding.HASHED_VERSION_1,
            block.chainid,
            address(0)
        );

        if (recoveredSigner == address(0)) {
            return (false, address(0), recoveredSigner);
        }

        isValid = isAuthorizedToCreatePremint(recoveredSigner, contractConfig.contractAdmin, contractAddress);
    }

    /// @notice Checks if the signer of a premint is authorized to sign a premint for a given contract.  If the contract hasn't been created yet,
    /// then the signer is authorized if the signer's address matches contractConfig.contractAdmin.  Otherwise, the signer must have the PERMISSION_BIT_MINTER
    /// role on the contract
    /// @param signer The signer of the premint
    /// @param premintContractConfigContractAdmin If this contract was created via premint, the original contractConfig.contractAdmin.  Otherwise, set to address(0)
    /// @param contractAddress The determinstic 1155 contract address the premint is for
    /// @return isAuthorized Whether the signer is authorized
    function isAuthorizedToCreatePremint(
        address signer,
        address premintContractConfigContractAdmin,
        address contractAddress
    ) public view returns (bool isAuthorized) {
        return ZoraCreator1155Attribution.isAuthorizedToCreatePremint(signer, premintContractConfigContractAdmin, contractAddress);
    }

    /// @notice Returns the versions of the premint signature that the contract supports
    /// @param contractAddress The address of the contract to check
    /// @return versions The versions of the premint signature that the contract supports.  If contract hasn't been created yet,
    /// assumes that when it will be created it will support the latest versions of the signatures, so the function returns all versions.
    function supportedPremintSignatureVersions(address contractAddress) external view returns (string[] memory versions) {
        // if contract hasn't been created yet, assume it will be created with the latest version
        // and thus supports all versions of the signature
        if (contractAddress.code.length == 0) {
            return DelegatedTokenCreation._supportedPremintSignatureVersions();
        }

        IZoraCreator1155 creatorContract = IZoraCreator1155(contractAddress);
        if (
            creatorContract.supportsInterface(type(IZoraCreator1155DelegatedCreationLegacy).interfaceId) ||
            creatorContract.supportsInterface(type(IHasSupportedPremintSignatureVersions).interfaceId)
        ) {
            return IHasSupportedPremintSignatureVersions(contractAddress).supportedPremintSignatureVersions();
        }

        // try get token id for uid 0 - if call fails, we know this didn't support premint
        try ERC1155DelegationStorageV1(contractAddress).delegatedTokenId(uint32(0)) returns (uint256) {
            versions = new string[](1);
            versions[0] = PremintEncoding.VERSION_1;
        } catch {
            versions = new string[](0);
        }
    }

    // upgrade related functionality

    /// @notice The name of the contract for upgrade purposes
    function contractName() external pure returns (string memory) {
        return "ZORA 1155 Premint Executor";
    }

    // upgrade functionality
    /// @notice Returns the current implementation address
    function implementation() external view returns (address) {
        return _getImplementation();
    }

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

    function mintFee(address collectionAddress) external view returns (uint256) {
        if (collectionAddress.code.length == 0) {
            return ZoraCreator1155FactoryImpl(address(zora1155Factory)).zora1155Impl().mintFee();
        }

        return IZoraCreator1155(collectionAddress).mintFee();
    }
}
