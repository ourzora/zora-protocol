// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {EIP712UpgradeableWithChainId} from "./EIP712UpgradeableWithChainId.sol";
import {ECDSAUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreator1155FactoryImpl} from "../factory/ZoraCreator1155FactoryImpl.sol";
import {ZoraCreator1155Impl} from "../nft/ZoraCreator1155Impl.sol";
import {ZoraCreator1155StorageV1} from "../nft/ZoraCreator1155StorageV1.sol";
import {SharedBaseConstants} from "../shared/SharedBaseConstants.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";

/// @title Enables a creator to signal intent to create a Zora erc1155 contract or new token on that
/// contract by signing a transaction but not paying gas, and have a third party/collector pay the gas
/// by executing the transaction.  Incentivizes the third party to execute the transaction by offering
/// a reward in the form of minted tokens.
/// @author @oveddan
contract ZoraCreator1155Preminter is EIP712UpgradeableWithChainId, Ownable2StepUpgradeable {
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

    /// @notice Contract creation parameters unique hash => created contract address
    mapping(uint256 => address) public contractAddresses;
    /// @dev hash of contract creation config + token uid -> if token has been created
    mapping(uint256 => bool) tokenCreated;

    error TokenAlreadyCreated();

    function initialize(ZoraCreator1155FactoryImpl _factory) public initializer {
        __EIP712_init("Preminter", "0.0.1");
        factory = _factory;
        fixedPriceMinter = _factory.fixedPriceMinter();
    }

    struct ContractCreationConfig {
        /// @notice Creator/admin of the created contract.  Must match the account that signed the message
        address contractAdmin;
        /// @notice Metadata URI for the created contract
        string contractURI;
        /// @notice Name of the created contract
        string contractName;
    }

    struct TokenCreationConfig {
        /// @notice Metadata URI for the created token
        string tokenURI;
        /// @notice Max supply of the created token
        uint256 maxSupply;
        /// @notice Max tokens that can be minted for an address, 0 if unlimited
        uint64 maxTokensPerAddress;
        /// @notice Price per token in eth wei. 0 for a free mint.
        uint96 pricePerToken;
        /// @notice The duration of the sale, starting from the first mint of this token. 0 for infinite
        uint64 saleDuration;
        /// @notice RoyaltyMintSchedule for created tokens. Every nth token will go to the royalty recipient.
        uint32 royaltyMintSchedule;
        /// @notice RoyaltyBPS for created tokens. The royalty amount in basis points for secondary sales.
        uint32 royaltyBPS;
        /// @notice RoyaltyRecipient for created tokens. The address that will receive the royalty payments.
        address royaltyRecipient;
    }

    struct PremintConfig {
        /// @notice The config for the contract to be created
        ContractCreationConfig contractConfig;
        /// @notice The config for the token to be created
        TokenCreationConfig tokenConfig;
        /// @notice Unique id of the token, used to ensure that multiple signatures can't be used to create the same intended token.
        /// only one signature per token id, scoped to the contract hash can be executed.
        uint32 uid;
        /// @notice Version of this config, scoped to the uid.  Not used for logic in the contract.
        uint32 version;
    }

    event Preminted(
        address indexed contractAddress,
        uint256 indexed tokenId,
        bool indexed createdNewContract,
        uint256 contractHashId,
        uint32 uid,
        ContractCreationConfig contractConfig,
        TokenCreationConfig tokenConfig,
        address minter,
        uint256 quantityMinted
    );

    // same signature should work whether or not there is an existing contract
    // so it is unaware of order, it just takes the token uri and creates the next token with it
    // this could include creating the contract.
    // do we need a deadline? open q
    function premint(
        PremintConfig calldata premintConfig,
        /// @notice Unique id of the token, used to ensure that multiple signatures can't be used to create the same intended token, in the case
        /// that a signature is updated for a token, and the old signature is executed, two tokens for the same original intended token could be created.
        /// Only one signature per token id, scoped to the contract hash can be executed.
        bytes calldata signature,
        uint256 quantityToMint,
        string calldata mintComment
    ) public payable returns (address contractAddress, uint256 newTokenId) {
        // 1. Validate the signature, and mark it as used.
        // 2. Create an erc1155 contract with the given name and uri and the creator as the admin/owner
        // 3. Allow this contract to create new new tokens on the contract
        // 4. Mint a new token, and get the new token id
        // 5. Setup fixed price minting rules for the new token
        // 6. Make the creator an admin of that token (and remove this contracts admin rights)
        // 7. Mint x tokens, as configured, to the executor of this transaction.
        // validate the signature for the current chain id, and make sure it hasn't been used, marking
        // that it has been used
        _validateSignatureAndEnsureNotUsed(premintConfig, signature);

        ContractCreationConfig calldata contractConfig = premintConfig.contractConfig;
        TokenCreationConfig calldata tokenConfig = premintConfig.tokenConfig;

        // get or create the contract with the given params
        (IZoraCreator1155 tokenContract, uint256 contractHash, bool isNewContract) = _getOrCreateContract(contractConfig);
        contractAddress = address(tokenContract);

        // setup the new token, and its sales config
        newTokenId = _setupNewTokenAndSale(tokenContract, contractConfig.contractAdmin, tokenConfig);

        emit Preminted(contractAddress, newTokenId, isNewContract, contractHash, premintConfig.uid, contractConfig, tokenConfig, msg.sender, quantityToMint);

        // mint the initial x tokens for this new token id to the executor.
        address tokenRecipient = msg.sender;
        tokenContract.mint{value: msg.value}(fixedPriceMinter, newTokenId, quantityToMint, abi.encode(tokenRecipient, mintComment));
    }

    function _getOrCreateContract(
        ContractCreationConfig calldata contractConfig
    ) private returns (IZoraCreator1155 tokenContract, uint256 contractHash, bool isNewContract) {
        contractHash = contractDataHash(contractConfig);
        address contractAddress = contractAddresses[contractHash];
        // first we see if the address exists for the contract
        isNewContract = contractAddress == address(0);
        if (isNewContract) {
            // if address doesnt exist for hash, createi t
            tokenContract = _createContract(contractConfig);
            contractAddresses[contractHash] = address(tokenContract);
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
        address newContractAddresss = factory.createContract(
            contractConfig.contractURI,
            contractConfig.contractName,
            // default royalty config is empty, since we set it on a token level
            ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyBPS: 0, royaltyRecipient: address(0), royaltyMintSchedule: 0}),
            payable(contractConfig.contractAdmin),
            setupActions
        );
        tokenContract = IZoraCreator1155(newContractAddresss);
    }

    function _setupNewTokenAndSale(
        IZoraCreator1155 tokenContract,
        address contractAdmin,
        TokenCreationConfig calldata tokenConfig
    ) private returns (uint256 newTokenId) {
        // mint a new token, and get its token id
        // this contract has admin rights on that token

        newTokenId = tokenContract.setupNewToken(tokenConfig.tokenURI, tokenConfig.maxSupply);

        // set up the sales strategy
        // first, grant the fixed price sale strategy minting capabilities on the token
        tokenContract.addPermission(newTokenId, address(fixedPriceMinter), PERMISSION_BIT_MINTER);

        // set the sales config on that token
        tokenContract.callSale(
            newTokenId,
            fixedPriceMinter,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                newTokenId,
                _buildNewSalesConfig(contractAdmin, tokenConfig.pricePerToken, tokenConfig.maxTokensPerAddress, tokenConfig.saleDuration)
            )
        );

        // set the royalty config on that token:
        tokenContract.updateRoyaltiesForToken(
            newTokenId,
            ICreatorRoyaltiesControl.RoyaltyConfiguration({
                royaltyBPS: tokenConfig.royaltyBPS,
                royaltyRecipient: tokenConfig.royaltyRecipient,
                royaltyMintSchedule: tokenConfig.royaltyMintSchedule
            })
        );

        // remove this contract as admin of the newly created token:
        tokenContract.removePermission(newTokenId, address(this), PERMISSION_BIT_ADMIN);
    }

    function recoverSigner(PremintConfig calldata premintConfig, bytes calldata signature) public view returns (address signatory) {
        // first validate the signature - the creator must match the signer of the message
        bytes32 digest = premintHashData(
            premintConfig,
            // here we pass the current contract and chain id, ensuring that the message
            // only works for the current chain and contract id
            address(this),
            block.chainid
        );

        signatory = ECDSAUpgradeable.recover(digest, signature);
    }

    /// Gets hash data to sign for a premint.  Allows specifying a different chain id and contract address so that the signature
    /// can be verified on a different chain.
    /// @param premintConfig Premint config to hash
    /// @param verifyingContract Contract address that signature is to be verified against
    /// @param chainId Chain id that signature is to be verified on
    function premintHashData(PremintConfig calldata premintConfig, address verifyingContract, uint256 chainId) public view returns (bytes32) {
        bytes32 encoded = _hashPremintConfig(premintConfig);

        // build the struct hash to be signed
        // here we pass the chain id, allowing the message to be signed for another chain
        return _hashTypedDataV4(encoded, verifyingContract, chainId);
    }

    bytes32 constant CONTRACT_AND_TOKEN_DOMAIN =
        keccak256(
            "Premint(ContractCreationConfig contractConfig,TokenCreationConfig tokenConfig,uint32 uid,uint32 version)ContractCreationConfig(address contractAdmin,string contractURI,string contractName)TokenCreationConfig(string tokenURI,uint256 maxSupply,uint64 maxTokensPerAddress,uint96 pricePerToken,uint64 saleDuration,uint32 royaltyMintSchedule,uint32 royaltyBPS,address royaltyRecipient)"
        );

    function _hashPremintConfig(PremintConfig calldata premintConfig) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    CONTRACT_AND_TOKEN_DOMAIN,
                    _hashContract(premintConfig.contractConfig),
                    _hashToken(premintConfig.tokenConfig),
                    premintConfig.uid,
                    premintConfig.version
                )
            );
    }

    bytes32 constant TOKEN_DOMAIN =
        keccak256(
            "TokenCreationConfig(string tokenURI,uint256 maxSupply,uint64 maxTokensPerAddress,uint96 pricePerToken,uint64 saleDuration,uint32 royaltyMintSchedule,uint32 royaltyBPS,address royaltyRecipient)"
        );

    function _hashToken(TokenCreationConfig calldata tokenConfig) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    TOKEN_DOMAIN,
                    stringHash(tokenConfig.tokenURI),
                    tokenConfig.maxSupply,
                    tokenConfig.maxTokensPerAddress,
                    tokenConfig.pricePerToken,
                    tokenConfig.saleDuration,
                    tokenConfig.royaltyMintSchedule,
                    tokenConfig.royaltyBPS,
                    tokenConfig.royaltyRecipient
                )
            );
    }

    bytes32 constant CONTRACT_DOMAIN = keccak256("ContractCreationConfig(address contractAdmin,string contractURI,string contractName)");

    function _hashContract(ContractCreationConfig calldata contractConfig) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(CONTRACT_DOMAIN, contractConfig.contractAdmin, stringHash(contractConfig.contractURI), stringHash(contractConfig.contractName))
            );
    }

    function tokenHasBeenCreated(ContractCreationConfig calldata contractConfig, uint256 tokenUid) public view returns (bool) {
        return tokenCreated[contractAndTokenHash(contractConfig, tokenUid)];
    }

    function contractAndTokenHash(ContractCreationConfig calldata contractConfig, uint256 tokenUid) public pure returns (uint256) {
        return
            uint256(
                keccak256(abi.encode(contractConfig.contractAdmin, stringHash(contractConfig.contractURI), stringHash(contractConfig.contractName), tokenUid))
            );
    }

    function _validateSignatureAndEnsureNotUsed(PremintConfig calldata premintConfig, bytes calldata signature) private returns (uint256 tokenHash) {
        // first validate the signature - the creator must match the signer of the message
        address signatory = recoverSigner(premintConfig, signature);

        ContractCreationConfig calldata contractConfig = premintConfig.contractConfig;

        if (signatory != contractConfig.contractAdmin) {
            revert("Invalid signature");
        }

        // make sure that this signature hasn't been used
        // token hash includes the contract hash, so we can check uniqueness of contract + token pair
        tokenHash = contractAndTokenHash(contractConfig, premintConfig.uid);
        if (tokenCreated[tokenHash]) {
            revert TokenAlreadyCreated();
        }
        tokenCreated[tokenHash] = true;

        return tokenHash;
    }

    /// Returns a unique hash for the contract data, useful to uniquely identify a contract based on creation params
    /// and determining what contract address has been created for this hash.  Also used to scope
    /// unique unique ids associated with signatures, the uid field on TokenCreationConfig
    function contractDataHash(ContractCreationConfig calldata contractConfig) public pure returns (uint256) {
        return uint256(_hashContract(contractConfig));
    }

    function stringHash(string calldata value) private pure returns (bytes32) {
        return keccak256(bytes(value));
    }

    function _buildNewSalesConfig(
        address creator,
        uint96 pricePerToken,
        uint64 maxTokensPerAddress,
        uint64 duration
    ) private view returns (ZoraCreatorFixedPriceSaleStrategy.SalesConfig memory) {
        uint64 saleStart = uint64(block.timestamp);
        uint64 saleEnd = duration == 0 ? type(uint64).max : saleStart + duration;

        return
            ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                pricePerToken: pricePerToken,
                saleStart: saleStart,
                saleEnd: saleEnd,
                maxTokensPerAddress: maxTokensPerAddress,
                fundsRecipient: creator
            });
    }
}
