// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {ECDSAUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {SharedBaseConstants} from "../shared/SharedBaseConstants.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {PremintConfig, ContractCreationConfig, TokenCreationConfig, ZoraCreator1155Attribution} from "./ZoraCreator1155Attribution.sol";

/// @title Enables a creator to signal intent to create a Zora erc1155 contract or new token on that
/// contract by signing a transaction but not paying gas, and have a third party/collector pay the gas
/// by executing the transaction.  Incentivizes the third party to execute the transaction by offering
/// a reward in the form of minted tokens.
/// @author @oveddan
contract ZoraCreator1155PremintExecutor {
    IZoraCreator1155Factory factory;

    /// @notice copied from SharedBaseConstants
    uint256 constant CONTRACT_BASE_ID = 0;
    /// @dev copied from ZoraCreator1155Impl
    uint256 constant PERMISSION_BIT_MINTER = 2 ** 2;

    error MintNotYetStarted();
    error InvalidSignature();

    // todo: make a constructor
    constructor(IZoraCreator1155Factory _factory) {
        factory = _factory;
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

    // same signature should work whether or not there is an existing contract
    // so it is unaware of order, it just takes the token uri and creates the next token with it
    // this could include creating the contract.
    function premint(
        ContractCreationConfig calldata contractConfig,
        PremintConfig calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        string calldata mintComment
    ) public payable returns (uint256 newTokenId) {
        // 1. Validate the signature.
        // 2. get or create an erc1155 contract with the same determinsitic address as that from the contract config
        // 3. Have the erc1155 contract create a new token.  the signer must have permission to do mint new tokens
        // (that role enforcement is expected to be in the tokenContract).
        // 4. The erc1155 will sedtup the token with the signign address as the creator, and follow the creator rewards standard.
        // 5. Mint x tokens, as configured, to the executor of this transaction.
        // 6. Future: First minter gets rewards

        // get or create the contract with the given params
        (IZoraCreator1155 tokenContract, bool isNewContract) = _getOrCreateContract(contractConfig);
        address contractAddress = address(tokenContract);

        // have the address setup the new token.  The signer must have permission to do this.
        // (that role enforcement is expected to be in the tokenContract).
        // the token contract will:

        // * setup the token with the signer as the creator, and follow the creator rewards standard.
        // * will revert if the token in the contract with the same uid already exists.
        // * will make sure creator has admin rights to the token.
        // * setup the token with the given token config.
        // * return the new token id.
        newTokenId = tokenContract.delegateSetupNewToken(premintConfig, signature);

        // mint the initial x tokens for this new token id to the executor.
        address tokenRecipient = msg.sender;

        tokenContract.mint{value: msg.value}(
            IMinter1155(premintConfig.tokenConfig.fixedPriceMinter),
            newTokenId,
            quantityToMint,
            abi.encode(tokenRecipient, mintComment)
        );

        // emit Preminted event
        emit Preminted(contractAddress, newTokenId, isNewContract, premintConfig.uid, contractConfig, premintConfig.tokenConfig, msg.sender, quantityToMint);
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
        address newContractAddresss = factory.createContractDeterministic(
            contractConfig.contractURI,
            contractConfig.contractName,
            // default royalty config is empty, since we set it on a token level
            ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyBPS: 0, royaltyRecipient: address(0), royaltyMintSchedule: 0}),
            payable(contractConfig.contractAdmin),
            setupActions
        );
        tokenContract = IZoraCreator1155(newContractAddresss);
    }

    function getContractAddress(ContractCreationConfig calldata contractConfig) public view returns (address) {
        return factory.deterministicContractAddress(address(this), contractConfig.contractURI, contractConfig.contractName, contractConfig.contractAdmin);
    }

    function recoverSigner(PremintConfig calldata premintConfig, address zor1155Address, bytes calldata signature) public view returns (address) {
        return ZoraCreator1155Attribution.recoverSigner(premintConfig, signature, zor1155Address, block.chainid);
    }

    /// @notice Utility function to determine if a premint contract has been created for a uid of a premint, and if so,
    /// What is the token id that was created for the uid.
    function premintStatus(address contractAddress, uint32 uid) public view returns (bool contractCreated, uint256 tokenIdForPremint) {
        if (contractAddress.code.length == 0) {
            return (false, 0);
        }
        return (true, IZoraCreator1155(contractAddress).delegatedTokenId(uid));
    }

    /// @notice Utility function to check if the signature is valid; i.e. the signature can be used to
    /// mint a token with the given config.  If contract hasn't been created, then the signer
    /// must match the contract admin on the premint config.
    /// If it has been created, the signer must have permission to mint new tokens on the erc1155 contract.
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
}
