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
import {PremintConfig, ContractCreationConfig, TokenCreationConfig, ZoraCreator1155Attribution} from "./ZoraCreator1155Attribution.sol";

/// @title Enables creation of and minting tokens on Zora1155 contracts transactions using eip-712 signatures.
/// Signature must provided by the contract creator, or an account that's permitted to create new tokens on the contract.
/// Mints the first x tokens to the executor of the transaction.
/// @author @oveddan
contract ZoraCreator1155PremintExecutorImpl is Ownable2StepUpgradeable, UUPSUpgradeable, IHasContractName, IZoraCreator1155Errors {
    IZoraCreator1155Factory public immutable zora1155Factory;

    /// @notice copied from SharedBaseConstants
    uint256 constant CONTRACT_BASE_ID = 0;
    /// @dev copied from ZoraCreator1155Impl
    uint256 constant PERMISSION_BIT_MINTER = 2 ** 2;

    constructor(IZoraCreator1155Factory _factory) {
        zora1155Factory = _factory;
    }

    function initialize(address _initialOwner) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();
    }

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

    /// Creates a new token on the given erc1155 contract on behalf of a creator, and mints x tokens to the executor of this transaction.
    /// If the erc1155 contract hasn't been created yet, it will be created with the given config within this same transaction.
    /// The creator must sign the intent to create the token, and must have mint new token permission on the erc1155 contract,
    /// or match the contract admin on the contract creation config if the contract hasn't been created yet.
    /// Contract address of the created contract is deterministically generated from the contract config and this contract's address.
    /// @param contractConfig Parameters for creating a new contract, if one doesn't exist yet.  Used to resolve the deterministic contract address.
    /// @param premintConfig Parameters for creating the token, and minting the initial x tokens to the executor.
    /// @param signature Signature of the creator of the token, which must match the signer of the premint config, or have permission to create new tokens on the erc1155 contract if it's already been created
    /// @param quantityToMint How many tokens to mint to the executor of this transaction once the token is created
    /// @param mintComment A comment to associate with the mint action
    function premint(
        ContractCreationConfig calldata contractConfig,
        PremintConfig calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        string calldata mintComment
    ) public payable returns (uint256 newTokenId) {
        // get or create the contract with the given params
        // contract address is deterministic.
        (IZoraCreator1155 tokenContract, bool isNewContract) = _getOrCreateContract(contractConfig);

        // pass the signature and the premint config to the token contract to create the token.
        // The token contract will verify the signature and that the signer has permission to create a new token.
        // and then create and setup the token using the given token config.
        newTokenId = tokenContract.delegateSetupNewToken(premintConfig, signature, msg.sender);

        // if the executor would also like to mint:
        if (quantityToMint != 0) {
            // mint the number of specified tokens to the executor
            tokenContract.mint{value: msg.value}(
                IMinter1155(premintConfig.tokenConfig.fixedPriceMinter),
                newTokenId,
                quantityToMint,
                abi.encode(msg.sender, mintComment)
            );
        }

        // emit Preminted event
        emit Preminted(
            address(tokenContract),
            newTokenId,
            isNewContract,
            premintConfig.uid,
            contractConfig,
            premintConfig.tokenConfig,
            msg.sender,
            quantityToMint
        );
    }

    function _getOrCreateContract(ContractCreationConfig calldata contractConfig) private returns (IZoraCreator1155 tokenContract, bool isNewContract) {
        address contractAddress = getContractAddress(contractConfig);
        // first we see if the code is already deployed for the contract
        isNewContract = contractAddress.code.length == 0;

        if (isNewContract) {
            // if address doesnt exist for hash, createi t
            tokenContract = _createContract(contractConfig);
        } else {
            tokenContract = IZoraCreator1155(contractAddress);
        }
    }

    function _createContract(ContractCreationConfig calldata contractConfig) private returns (IZoraCreator1155 tokenContract) {
        // we need to build the setup actions, that must:
        bytes[] memory setupActions = new bytes[](0);

        // create the contract via the factory.
        address newContractAddresss = zora1155Factory.createContractDeterministic(
            contractConfig.contractURI,
            contractConfig.contractName,
            // default royalty config is empty, since we set it on a token level
            ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyBPS: 0, royaltyRecipient: address(0), royaltyMintSchedule: 0}),
            payable(contractConfig.contractAdmin),
            setupActions
        );
        tokenContract = IZoraCreator1155(newContractAddresss);
    }

    /// Gets the deterministic contract address for the given contract creation config.
    /// Contract address is generated deterministically from a hash based onthe contract uri, contract name,
    /// contract admin, and the msg.sender, which is this contract's address.
    function getContractAddress(ContractCreationConfig calldata contractConfig) public view returns (address) {
        return
            zora1155Factory.deterministicContractAddress(address(this), contractConfig.contractURI, contractConfig.contractName, contractConfig.contractAdmin);
    }

    /// Recovers the signer of the given premint config created against the specified zora1155 contract address.
    function recoverSigner(PremintConfig calldata premintConfig, address zor1155Address, bytes calldata signature) public view returns (address) {
        return ZoraCreator1155Attribution.recoverSigner(premintConfig, signature, zor1155Address, block.chainid);
    }

    /// @notice Utility function to determine if a premint contract has been created for a uid of a premint, and if so,
    /// What is the token id that was created for the uid.
    function premintStatus(address contractAddress, uint32 uid) public view returns (bool contractCreated, uint256 tokenIdForPremint) {
        if (contractAddress.code.length == 0) {
            return (false, 0);
        }
        return (true, ERC1155DelegationStorageV1(contractAddress).delegatedTokenId(uid));
    }

    /// @notice Utility function to check if the signature is valid; i.e. the signature can be used to
    /// mint a token with the given config.  If the contract hasn't been created, then the signer
    /// must match the contract admin on the premint config. If it has been created, the signer
    /// must have permission to create new tokens on the erc1155 contract.
    function isValidSignature(
        ContractCreationConfig calldata contractConfig,
        PremintConfig calldata premintConfig,
        bytes calldata signature
    ) public view returns (bool isValid, address contractAddress, address recoveredSigner) {
        contractAddress = getContractAddress(contractConfig);
        recoveredSigner = recoverSigner(premintConfig, contractAddress, signature);

        if (recoveredSigner == address(0)) {
            return (false, contractAddress, address(0));
        }

        // if contract hasn't been created, signer must be the contract admin on the config
        if (contractAddress.code.length == 0) {
            isValid = recoveredSigner == contractConfig.contractAdmin;
        } else {
            // if contract has been created, signer must have mint new token permission
            isValid = IZoraCreator1155(contractAddress).isAdminOrRole(recoveredSigner, CONTRACT_BASE_ID, PERMISSION_BIT_MINTER);
        }
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
}
