// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {ECDSAUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {SharedBaseConstants} from "../shared/SharedBaseConstants.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {PremintConfig, ContractCreationConfig, TokenCreationConfig} from "./ZoraCreator1155Delegation.sol";

/// @title Enables a creator to signal intent to create a Zora erc1155 contract or new token on that
/// contract by signing a transaction but not paying gas, and have a third party/collector pay the gas
/// by executing the transaction.  Incentivizes the third party to execute the transaction by offering
/// a reward in the form of minted tokens.
/// @author @oveddan
contract ZoraCreator1155Preminter is Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {
    IZoraCreator1155Factory factory;
    IMinter1155 fixedPriceMinter;

    /// @notice copied from SharedBaseConstants
    uint256 constant CONTRACT_BASE_ID = 0;
    /// @notice This user role allows for any action to be performed
    /// @dev copied from ZoraCreator1155Impl
    uint256 constant PERMISSION_BIT_ADMIN = 2 ** 1;
    /// @notice This user role allows for only mint actions to be performed.
    /// @dev copied from ZoraCreator1155Impl
    uint256 constant PERMISSION_BIT_MINTER = 2 ** 2;
    uint256 constant PERMISSION_BIT_SALES = 2 ** 3;

    error MintNotYetStarted();
    error InvalidSignature();

    function initialize(IZoraCreator1155Factory _factory) public initializer {
        factory = _factory;
        fixedPriceMinter = _factory.defaultMinters()[0];
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
        PremintConfig calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        string calldata mintComment
    ) public payable nonReentrant returns (address contractAddress, uint256 newTokenId) {
        // 1. Validate the signature.
        // 2. Create an erc1155 contract with the given name and uri and the creator as the admin/owner
        // 3. Allow this contract to create new new tokens on the contract
        // 4. Mint a new token, and get the new token id
        // 5. Setup fixed price minting rules for the new token
        // 6. Make the creator an admin of that token (and remove this contracts admin rights)
        // 7. Mint x tokens, as configured, to the executor of this transaction.

        // get or create the contract with the given params
        (IZoraCreator1155 tokenContract, bool isNewContract) = _getOrCreateContract(premintConfig.contractConfig);
        contractAddress = address(tokenContract);

        tokenContract.delegateSetupNewToken(premintConfig, signature);

        // mint the initial x tokens for this new token id to the executor.
        address tokenRecipient = msg.sender;
        tokenContract.mint{value: msg.value}(fixedPriceMinter, newTokenId, quantityToMint, abi.encode(tokenRecipient, mintComment));

        emit Preminted(
            contractAddress,
            newTokenId,
            isNewContract,
            premintConfig.uid,
            premintConfig.contractConfig,
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
        // grant this contract ability to mint tokens - when a token is minted, this contract is
        // granted admin rights on that token
        bytes[] memory setupActions = new bytes[](1);
        setupActions[0] = abi.encodeWithSelector(IZoraCreator1155.addPermission.selector, CONTRACT_BASE_ID, address(this), PERMISSION_BIT_MINTER);

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
}
