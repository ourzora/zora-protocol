// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {EIP712UpgradeableWithChainId} from "./EIP712UpgradeableWithChainId.sol";
import {ECDSAUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreator1155Impl} from "../nft/ZoraCreator1155Impl.sol";
import {SharedBaseConstants} from "../shared/SharedBaseConstants.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";

/// @title Enables a creator to signal intent to create a Zora erc1155 contract or new token on that
/// contract by signing a transaction but not paying gas, and have a third party/collector pay the gas
/// by executing the transaction.  Incentivizes the third party to execute the transaction by offering
/// a reward in the form of minted tokens.
/// @author @oveddan
/// @notice
contract ZoraCreator1155Preminter is EIP712UpgradeableWithChainId {
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

    /// @notice Contract creation parameters unique hash => created contract address
    mapping(uint256 => address) public contractAddresses;
    /// @dev Signature unique hash => signature used
    mapping(uint256 => bool) signatureUsed;

    mapping(address => mapping(uint256 => TokenUpdate)) tokenUpdates;

    // creator => update nonce
    mapping(address => uint256) public nonces;

    function initialize(IZoraCreator1155Factory _factory, IMinter1155 _fixedPriceMinter) public initializer {
        __EIP712_init("Preminter", "0.0.1");
        factory = _factory;
        fixedPriceMinter = _fixedPriceMinter;
    }

    // todo: optimize storage layout
    struct ContractConfig {
        /// @notice Metadata URI for the created contract
        string contractURI;
        /// @notice Name of the created contract
        string contractName;
        /// @notice royaltyMintSchedule Every nth token will go to the royalty recipient.
        uint32 royaltyMintSchedule;
        /// @notice royaltyBPS The royalty amount in basis points for secondary sales.
        uint32 royaltyBPS;
        /// @notice royaltyRecipient The address that will receive the royalty payments.
        address royaltyRecipient;
    }

    // todo: optimize storage layout
    struct TokenConfig {
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
    }

    struct TokenUpdate {
        bool exists;
        TokenConfig tokenConfig;
    }

    // same signature should work whether or not there is an existing contract
    // so it is unaware of order, it just takes the token uri and creates the next token with it
    // this could include creating the contract.
    // do we need a deadline? open q
    function premint(
        address signer,
        ContractConfig calldata contractConfig,
        TokenConfig calldata tokenConfig,
        uint256 quantityToMint,
        bytes calldata signature
    ) public payable returns (uint256 newTokenId) {
        // 1. Validate the signature, and mark it as used.
        // 2. Create an erc1155 contract with the given name and uri and the creator as the admin/owner
        // 3. Allow this contract to create new new tokens on the contract
        // 4. Mint a new token, and get the new token id
        // 5. Setup fixed price minting rules for the new token
        // 6. Make the creator an admin of that token (and remove this contracts admin rights)
        // 7. Mint x tokens, as configured, to the executor of this transaction.

        // validate the signature for the current chain id, and make sure it hasn't been used, marking
        // that it has been used
        uint256 tokenHash = _validateSignatureAndEnsureNotUsed(signer, contractConfig, tokenConfig, signature);

        // get or create the contract with the given params
        IZoraCreator1155 tokenContract = _getOrCreateContract(signer, contractConfig);

        // setup the new token, and its sales config
        newTokenId = _setupNewTokenAndSale(tokenContract, signer, getCurrentTokenConfig(signer, tokenConfig, tokenHash));

        // mint the initial x tokens for this new token id to the executor.
        address tokenRecipient = msg.sender;
        tokenContract.mint{value: msg.value}(fixedPriceMinter, newTokenId, quantityToMint, abi.encode(tokenRecipient, ""));
    }

    /// Stores an update to a premint token that will apply when the token is created.
    /// Uses a signature to ensure that the token creator is the one who created the update to the token.
    /// Can be executed by any account with the signature
    /// @param tokenCreator The address of the creator of the token
    /// @param tokenHash The hash of the token to be updated
    /// @param newTokenConfig The new token config to be applied when the token is created
    /// @param nonce The nonce of the update, to ensure that updates are applied in order.
    /// @param signature The signature of the token creator for the token hash and new token config
    function updatePremint(address tokenCreator, uint256 tokenHash, TokenConfig calldata newTokenConfig, uint256 nonce, bytes calldata signature) public {
        // check that the token has not been created yet - if it has, this update won't do anything so we just revert.
        require(signatureUsed[tokenHash] == false, "Token already created");

        // increment the nonce - this ensures updates arrive in order
        require(nonces[tokenCreator]++ == nonce, "Invalid nonce");

        // validate the signature for the token hash and new tokenConfig
        (address signer, ) = recoverPremintUpdateSigner(tokenCreator, tokenHash, newTokenConfig, nonce, signature);
        require(signer == tokenCreator, "Invalid signature");

        // save the update - since this is scoped within the creator, its fine if they spoof the token hash
        // it'll just affect their own tokens
        tokenUpdates[tokenCreator][tokenHash] = TokenUpdate(true, newTokenConfig);
    }

    /// @notice gets the current token config for a token to be preminted, by retrieving the update if it exists
    function getCurrentTokenConfig(address creator, TokenConfig calldata tokenConfig, uint256 tokenHash) public view returns (TokenConfig memory) {
        TokenUpdate storage tokenUpdate = tokenUpdates[creator][tokenHash];
        if (tokenUpdate.exists) {
            return tokenUpdate.tokenConfig;
        } else {
            return tokenConfig;
        }
    }

    function _getOrCreateContract(address contractAdmin, ContractConfig calldata contractConfig) private returns (IZoraCreator1155 tokenContract) {
        uint256 contractHash = contractDataHash(contractAdmin, contractConfig);
        address contractAddress = contractAddresses[contractHash];
        // if address already exists for hash, return it
        if (contractAddress != address(0)) {
            tokenContract = IZoraCreator1155(contractAddress);
        } else {
            // otherwise, create the contract and update the created contracts
            tokenContract = _createContract(contractAdmin, contractConfig);
            contractAddresses[contractHash] = address(tokenContract);
        }
    }

    function _createContract(address contractAdmin, ContractConfig calldata contractConfig) private returns (IZoraCreator1155 tokenContract) {
        // we need to build the setup actions, that must:
        // grant this contract ability to mint tokens - when a token is minted, this contract is
        // granted admin rights on that token
        bytes[] memory setupActions = new bytes[](1);
        setupActions[0] = abi.encodeWithSelector(IZoraCreator1155.addPermission.selector, CONTRACT_BASE_ID, address(this), PERMISSION_BIT_MINTER);

        ICreatorRoyaltiesControl.RoyaltyConfiguration memory royaltyConfig = ICreatorRoyaltiesControl.RoyaltyConfiguration({
            royaltyBPS: contractConfig.royaltyBPS,
            royaltyRecipient: contractConfig.royaltyRecipient,
            royaltyMintSchedule: contractConfig.royaltyMintSchedule
        });

        // create the contract via the factory.
        address newContractAddresss = factory.createContract(
            contractConfig.contractURI,
            contractConfig.contractName,
            royaltyConfig,
            payable(contractAdmin),
            setupActions
        );
        tokenContract = IZoraCreator1155(newContractAddresss);
    }

    function _setupNewTokenAndSale(IZoraCreator1155 tokenContract, address contractAdmin, TokenConfig memory tokenConfig) private returns (uint256 newTokenId) {
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
        // this contract is the admin of that token, and the creator isn't, so
        // make the creator the admin of that token, and remove this contracts admin rights on that token.
        tokenContract.addPermission(newTokenId, tokenContract.owner(), PERMISSION_BIT_ADMIN);
        tokenContract.removePermission(newTokenId, address(this), PERMISSION_BIT_ADMIN);
    }

    function recoverPremintSigner(
        address contractAdmin,
        ContractConfig calldata contractConfig,
        TokenConfig calldata tokenConfig,
        bytes calldata signature
    ) public view returns (address signatory, bytes32 digest) {
        // first validate the signature - the creator must match the signer of the message
        digest = premintHashData(
            contractAdmin,
            contractConfig,
            tokenConfig,
            // here we pass the current chain id, ensuring that the message
            // only works for the current chain id
            block.chainid
        );

        signatory = ECDSAUpgradeable.recover(digest, signature);
    }

    /// Recovers the signing account for a premint token update
    function recoverPremintUpdateSigner(
        /// Contract & token creator
        address premintCreator,
        /// The hash of the token to be updated
        uint256 tokenHash,
        /// Update to apply to the token.
        TokenConfig calldata newTokenConfig,
        uint256 nonce,
        bytes calldata signature
    ) public view returns (address signatory, bytes32 digest) {
        // first validate the signature - the creator must match the signer of the message
        digest = premintUpdateHashData(
            premintCreator,
            tokenHash,
            newTokenConfig,
            nonce,
            // here we pass the current chain id, ensuring that the message
            // only works for the current chain id
            block.chainid
        );

        signatory = ECDSAUpgradeable.recover(digest, signature);
    }

    bytes32 constant TOKEN_UPDATE =
        keccak256(
            "TokenUpdate(address contractAdmin,uint256 tokenHash,TokenConfig newTokenConfig,uint256 nonce)TokenConfig(string tokenURI,uint256 maxSupply,uint64 maxTokensPerAddress,uint96 pricePerToken,uint64 saleDuration)"
        );

    function premintUpdateHashData(
        address contractAdmin,
        uint256 tokenHash,
        TokenConfig calldata newTokenConfig,
        uint256 nonce,
        uint256 chainId
    ) public view returns (bytes32) {
        bytes32 encoded = keccak256(abi.encode(TOKEN_UPDATE, contractAdmin, tokenHash, _hashToken(newTokenConfig), nonce));

        // build the struct hash to be signed
        // here we pass the chain id, allowing the message to be signed for another chain
        return _hashTypedDataV4(encoded, chainId);
    }

    function premintHashData(
        address contractAdmin,
        ContractConfig calldata contractConfig,
        TokenConfig calldata tokenConfig,
        uint256 chainId
    ) public view returns (bytes32) {
        bytes32 encoded = _hashContractAndToken(contractAdmin, contractConfig, tokenConfig);

        // build the struct hash to be signed
        // here we pass the chain id, allowing the message to be signed for another chain
        return _hashTypedDataV4(encoded, chainId);
    }

    bytes32 constant CONTRACT_AND_TOKEN_DOMAIN =
        keccak256(
            "ContractAndToken(address contractAdmin,ContractConfig contractConfig,TokenConfig tokenConfig)ContractConfig(address contractAdmin,string contractURI,string contractName,uint32 royaltyMintSchedule,uint32 royaltyBPS,address royaltyRecipient)TokenConfig(string tokenURI,uint256 maxSupply,uint64 maxTokensPerAddress,uint96 pricePerToken,uint64 saleDuration)"
        );

    function _hashContractAndToken(
        address contractAdmin,
        ContractConfig calldata contractConfig,
        TokenConfig calldata tokenConfig
    ) private pure returns (bytes32) {
        return keccak256(abi.encode(CONTRACT_AND_TOKEN_DOMAIN, contractAdmin, _hashContract(contractConfig), _hashToken(tokenConfig)));
    }

    bytes32 constant TOKEN_DOMAIN =
        keccak256("TokenConfig(string tokenURI,uint256 maxSupply,uint64 maxTokensPerAddress,uint96 pricePerToken,uint64 saleDuration)");

    function _hashToken(TokenConfig calldata tokenConfig) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    TOKEN_DOMAIN,
                    stringHash(tokenConfig.tokenURI),
                    tokenConfig.maxSupply,
                    tokenConfig.maxTokensPerAddress,
                    tokenConfig.pricePerToken,
                    tokenConfig.saleDuration
                )
            );
    }

    bytes32 constant CONTRACT_DOMAIN =
        keccak256("ContractConfig(string contractURI,string contractName,uint32 royaltyMintSchedule,uint32 royaltyBPS,address royaltyRecipient)");

    function _hashContract(ContractConfig calldata contractConfig) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    CONTRACT_DOMAIN,
                    stringHash(contractConfig.contractURI),
                    stringHash(contractConfig.contractName),
                    contractConfig.royaltyMintSchedule,
                    contractConfig.royaltyBPS,
                    contractConfig.royaltyRecipient
                )
            );
    }

    function _validateSignatureAndEnsureNotUsed(
        address contractAdmin,
        ContractConfig calldata contractConfig,
        TokenConfig calldata tokenConfig,
        bytes calldata signature
    ) private returns (uint256 signatureAsUint) {
        // first validate the signature - the creator must match the signer of the message
        (address signatory, bytes32 digest) = recoverPremintSigner(contractAdmin, contractConfig, tokenConfig, signature);

        if (signatory != contractAdmin) {
            revert("Invalid signature");
        }

        signatureAsUint = uint256(digest);
        // make sure that this signature hasn't been used
        // token hash includes the contract hash, so we can check uniqueness of contract + token pair
        if (signatureUsed[signatureAsUint]) {
            revert("Signature already used");
        }
        signatureUsed[signatureAsUint] = true;
    }

    /// returns a unique hash for the contract data, useful to uniquely identify a contract based on creation params
    function contractDataHash(address contractAdmin, ContractConfig calldata contractConfig) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(contractAdmin, stringHash(contractConfig.contractURI), stringHash(contractConfig.contractName))));
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
