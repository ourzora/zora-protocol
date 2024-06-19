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
import {ZoraCreator1155PremintExecutorImplLib, GetOrCreateContractResult} from "./ZoraCreator1155PremintExecutorImplLib.sol";
import {ZoraCreator1155Attribution, DelegatedTokenCreation} from "./ZoraCreator1155Attribution.sol";
import {PremintEncoding} from "@zoralabs/shared-contracts/premint/PremintEncoding.sol";
import {ContractCreationConfig, ContractWithAdditionalAdminsCreationConfig, PremintConfig, PremintConfigV2, TokenCreationConfig, TokenCreationConfigV2, MintArguments, PremintResult, PremintConfigV3, TokenCreationConfigV3, PremintConfigEncoded} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {IZoraCreator1155PremintExecutor} from "../interfaces/IZoraCreator1155PremintExecutor.sol";
import {IZoraCreator1155DelegatedCreationLegacy, IHasSupportedPremintSignatureVersions} from "../interfaces/IZoraCreator1155DelegatedCreation.sol";
import {IZoraCreator1155PremintExecutorAllVersions} from "@zoralabs/shared-contracts/interfaces/IZoraCreator1155PremintExecutorAllVersions.sol";
import {ZoraCreator1155FactoryImpl} from "../factory/ZoraCreator1155FactoryImpl.sol";
import {IRewardsErrors} from "@zoralabs/protocol-rewards/src/interfaces/IRewardsErrors.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ContractVersionBase} from "../version/ContractVersionBase.sol";

/// @title Enables creation of and minting tokens on Zora1155 contracts transactions using eip-712 signatures.
/// Signature must provided by the contract creator, or an account that's permitted to create new tokens on the contract.
/// Mints the first x tokens to the executor of the transaction.
/// @author @oveddan
contract ZoraCreator1155PremintExecutorImpl is
    IZoraCreator1155PremintExecutor,
    IZoraCreator1155PremintExecutorAllVersions,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    IHasContractName,
    IZoraCreator1155Errors,
    IRewardsErrors,
    ContractVersionBase
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

    /// Creates a new token on the given erc1155 contract on behalf of a creator, and mints x tokens to the executor of this transaction.
    /// If a premintCollection parameter is provided, it will execute the premint against the collection at that address.
    /// If the premintCollection parameter is not provided, it will get or create an 1155 contract at a deterministic address using the contractConfig.
    /// The creator must sign the intent to create the token, and must have mint new token permission on the erc1155 contract,
    /// or match the contract admin on the contract creation config if the contract hasn't been created yet.
    /// Contract address of the created contract is deterministically generated from the contract config and this contract's address.
    /// @dev For use with of any version of premint config
    /// @param contractConfig Parameters for creating a new contract, if one doesn't exist yet.  Used to resolve the deterministic contract address.
    /// @param premintCollection If this parameter is provided, the premint will be executed against this contract address, and the contractConfig will be ignored.
    /// @param encodedPremintConfig abi encoded premint config
    /// @param signature Signature of the creator of the token, which must match the signer of the premint config, or have permission to create new tokens on the erc1155 contract if it's already been created
    /// @param quantityToMint How many tokens to mint to the mintRecipient
    /// @param mintArguments mint arguments specifying the token mint recipient, mint comment, and mint referral
    /// @param firstMinter account to get the firstMinter reward for the token
    /// @param signerContract If a smart wallet was used to create the premint, the address of that smart wallet. Otherwise, set to address(0)
    function premint(
        ContractWithAdditionalAdminsCreationConfig memory contractConfig,
        address premintCollection,
        PremintConfigEncoded memory encodedPremintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        MintArguments calldata mintArguments,
        address firstMinter,
        address signerContract
    ) public payable returns (PremintResult memory premintResult) {
        bool isNewContract = false;
        // if there is no premint collection, get or create the contract given deterministic params generated from the contract creation config
        if (premintCollection == address(0)) {
            (premintCollection, isNewContract) = ZoraCreator1155PremintExecutorImplLib.getOrCreateContract(zora1155Factory, contractConfig);
        }

        (bytes memory premintConfig, address minter) = PremintEncoding.decodePremintConfig(encodedPremintConfig);

        // get or create the token for the given premint config
        uint256 tokenId = ZoraCreator1155PremintExecutorImplLib.getOrCreateToken(
            IZoraCreator1155(premintCollection),
            premintConfig,
            encodedPremintConfig.premintConfigVersion,
            signature,
            firstMinter,
            signerContract
        );

        // if there tokens should be minted, mint quantityToMint of the token
        if (quantityToMint > 0) {
            if (
                encodedPremintConfig.premintConfigVersion == PremintEncoding.HASHED_VERSION_1 ||
                encodedPremintConfig.premintConfigVersion == PremintEncoding.HASHED_VERSION_2
            ) {
                ZoraCreator1155PremintExecutorImplLib.mintWithEth(IZoraCreator1155(premintCollection), minter, tokenId, quantityToMint, mintArguments);
            } else if (encodedPremintConfig.premintConfigVersion == PremintEncoding.HASHED_VERSION_3) {
                ZoraCreator1155PremintExecutorImplLib.performERC20Mint(minter, quantityToMint, premintCollection, tokenId, mintArguments);
            }
        }

        emit PremintedV2({
            contractAddress: premintCollection,
            tokenId: tokenId,
            createdNewContract: isNewContract,
            uid: encodedPremintConfig.uid,
            minter: msg.sender,
            quantityMinted: quantityToMint
        });

        return PremintResult({tokenId: tokenId, createdNewContract: isNewContract, contractAddress: premintCollection});
    }

    function _withEmptySetup(ContractCreationConfig calldata contractConfig) private pure returns (ContractWithAdditionalAdminsCreationConfig memory) {
        return
            ContractWithAdditionalAdminsCreationConfig({
                contractAdmin: contractConfig.contractAdmin,
                contractName: contractConfig.contractName,
                contractURI: contractConfig.contractURI,
                additionalAdmins: new address[](0)
            });
    }

    // @custom:deprecated use premint instead
    function premintV2(
        ContractCreationConfig calldata contractConfig,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        MintArguments calldata mintArguments
    ) external payable returns (PremintResult memory) {
        return
            premint(
                _withEmptySetup(contractConfig),
                address(0),
                PremintEncoding.encodePremint(premintConfig),
                signature,
                quantityToMint,
                mintArguments,
                msg.sender,
                address(0)
            );
    }

    // @custom:deprecated use premint instead
    function premintV1(
        ContractCreationConfig calldata contractConfig,
        PremintConfig calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        MintArguments calldata mintArguments
    ) external payable returns (PremintResult memory) {
        return
            premint(
                _withEmptySetup(contractConfig),
                address(0),
                PremintEncoding.encodePremint(premintConfig),
                signature,
                quantityToMint,
                mintArguments,
                msg.sender,
                address(0)
            );
    }

    /// @notice Gets the deterministic contract address for the given contract creation config.
    /// Contract address is generated deterministically from a hash based on the contract uri, contract name,
    /// contract admin, and the msg.sender, which is this contract's address.
    function getContractAddress(ContractCreationConfig calldata contractConfig) public view override returns (address) {
        return ZoraCreator1155PremintExecutorImplLib.getContractAddress(zora1155Factory, contractConfig);
    }

    /// @notice Gets the deterministic contract address for the given contract creation config.
    /// Contract address is generated deterministically from a hash based on the contract uri, contract name,
    /// contract admin, and the msg.sender, which is this contract's address.
    function getContractWithAdditionalAdminsAddress(ContractWithAdditionalAdminsCreationConfig calldata contractConfig) public view override returns (address) {
        return ZoraCreator1155PremintExecutorImplLib.getContractWithAdditionalAdminsAddress(zora1155Factory, contractConfig);
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
    /// @param contractAddress The deterministic 1155 contract address the premint is for
    /// @return isAuthorized Whether the signer is authorized
    function isAuthorizedToCreatePremint(
        address signer,
        address premintContractConfigContractAdmin,
        address contractAddress
    ) public view returns (bool isAuthorized) {
        return ZoraCreator1155PremintExecutorImplLib.isAuthorizedToCreatePremint(signer, premintContractConfigContractAdmin, contractAddress, new address[](0));
    }

    /// @notice Checks if the signer of a premint is authorized to sign a premint for a given contract.  If the contract hasn't been created yet,
    /// then the signer is authorized if the signer's address matches contractConfig.contractAdmin.  Otherwise, the signer must be
    /// in the list of additional admins
    /// @param signer The signer of the premint
    /// @param premintContractConfigContractAdmin If this contract was created via premint, the original contractConfig.contractAdmin.  Otherwise, set to address(0)
    /// @param contractAddress The deterministic 1155 contract address the premint is for
    /// @return isAuthorized Whether the signer is authorized
    function isAuthorizedToCreatePremintWithAdditionalAdmins(
        address signer,
        address premintContractConfigContractAdmin,
        address contractAddress,
        address[] calldata additionalAdmins
    ) public view returns (bool isAuthorized) {
        return ZoraCreator1155PremintExecutorImplLib.isAuthorizedToCreatePremint(signer, premintContractConfigContractAdmin, contractAddress, additionalAdmins);
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
