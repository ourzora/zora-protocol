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

contract Preminter is EIP712UpgradeableWithChainId {
    IZoraCreator1155Factory factory;
    ZoraCreatorFixedPriceSaleStrategy fixedPriceSaleStrategy;

    /// @notice copied from SharedBaseConstants
    uint256 constant CONTRACT_BASE_ID = 0;
    /// @notice This user role allows for any action to be performed
    /// @dev copied from ZoraCreator1155Impl
    uint256 public constant PERMISSION_BIT_ADMIN = 2 ** 1;
    /// @notice This user role allows for only mint actions to be performed.
    /// @dev copied from ZoraCreator1155Impl
    uint256 public constant PERMISSION_BIT_MINTER = 2 ** 2;

    mapping(uint256 => address) contractAddresses;
    mapping(uint256 => bool) signatureUsed;

    function initialize(IZoraCreator1155Factory _factory, ZoraCreatorFixedPriceSaleStrategy _fixedPriceSaleStrategy) public initializer {
        __EIP712_init("Preminter", "0.0.1");
        factory = _factory;
        fixedPriceSaleStrategy = _fixedPriceSaleStrategy;
    }

    struct PremintFixedPriceSalesConfig {
        /// @notice Max tokens that can be minted for an address, 0 if unlimited
        uint64 maxTokensPerAddress;
        /// @notice Price per token in eth wei. 0 for a free mint.
        uint96 pricePerToken;
        /// @notice The duration of the sale, starting from the first mint of this token. 0 for infinite
        uint64 duration;
    }

    struct ContractCreationConfig {
        address contractAdmin;
        string contractURI;
        string contractName;
        ICreatorRoyaltiesControl.RoyaltyConfiguration defaultRoyaltyConfiguration;
    }

    struct TokenCreationConfig {
        string tokenURI;
        uint256 tokenMaxSupply;
        PremintFixedPriceSalesConfig tokenSalesConfig;
    }

    // same signature should work whether or not there is an existing contract
    // so it is unaware of order, it just takes the token uri and creates the next token with it
    // this could include creating the contract.
    // do we need a deadline? open q

    function premint(
        ContractCreationConfig calldata contractConfig,
        TokenCreationConfig calldata tokenConfig,
        uint256 quantityToMint,
        bytes calldata signature
    ) public payable returns (uint256 newTokenId) {
        // This code must:
        // 2. Create an erc1155 contract with the given name and uri and the creator as the admin
        // 2. Allow this contract to set fixed price sale strategies on the created erc1155, and mint new tokens, so that in the future this contract can mint new tokens and set their rules
        // 3. Mint a new token, and get the new token id
        // 4. Setup fixed price minting rules for the new token
        // 5. Mint x tokens, as configured, to the executor of this transaction.

        // first validate the signature - the creator must match the signer of the message
        (bytes32 digest, uint256 contractHashId, uint256 tokenHash) = premintHashData(
            contractConfig,
            tokenConfig,
            quantityToMint,
            // here we pass the current chain id, ensuring that the message
            // only works for the current chain id
            block.chainid
        );

        // token hash includes the contract hash, so we can check uniqueness of contract + token pair
        if (signatureUsed[tokenHash]) {
            revert("Signature already used");
        }
        signatureUsed[tokenHash] = true;

        address signatory = ECDSAUpgradeable.recover(digest, signature);
        if (signatory != contractConfig.contractAdmin) {
            revert("Invalid signature");
        }

        IZoraCreator1155 tokenContract = _getOrCreateContract(contractConfig, contractHashId);

        _setupNewTokenAndSale(tokenContract, contractConfig.contractAdmin, tokenConfig);

        // we mint the initial x tokens for this new token id to the executor.
        address tokenRecipient = msg.sender;
        tokenContract.mint{value: msg.value}(fixedPriceSaleStrategy, newTokenId, quantityToMint, abi.encode(tokenRecipient, ""));
    }

    function _getOrCreateContract(ContractCreationConfig calldata contractConfig, uint256 contractHash) private returns (IZoraCreator1155 tokenContract) {
        address contractAddress = contractAddresses[contractHash];
        // if address already exists for hash, return it
        if (contractAddress != address(0)) {
            tokenContract = IZoraCreator1155(contractAddress);
        } else {
            // otherwise, create the contract and update the created contracts
            tokenContract = _createContract(contractConfig);
            contractAddresses[contractHash] = address(tokenContract);
        }
    }

    function _createContract(ContractCreationConfig calldata contractConfig) private returns (IZoraCreator1155 tokenContract) {
        // we need to build the setup actions, that must:
        // grant this contract ability to mint tokens - when a token is minted, this contract is
        // granted admin rights on that token
        bytes[] memory setupActions = new bytes[](2);
        setupActions[0] = abi.encodeWithSelector(IZoraCreator1155.addPermission.selector, CONTRACT_BASE_ID, address(this), PERMISSION_BIT_MINTER);

        // create the contract via the factory.
        address newContractAddresss = factory.createContract(
            contractConfig.contractURI,
            contractConfig.contractName,
            contractConfig.defaultRoyaltyConfiguration,
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
        // we then mint a new token, and get its token id
        newTokenId = tokenContract.setupNewToken(tokenConfig.tokenURI, tokenConfig.tokenMaxSupply);
        // we then set up the sales strategy
        // first we grant the fixed price sale strategy minting capabilities
        tokenContract.addPermission(newTokenId, address(fixedPriceSaleStrategy), PERMISSION_BIT_MINTER);
        // then we set the sales config
        tokenContract.callSale(
            newTokenId,
            fixedPriceSaleStrategy,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                newTokenId,
                _buildNewSalesConfig(contractAdmin, tokenConfig.tokenSalesConfig)
            )
        );
        // this contract is the admin of that token - lets make the contract
        // we make the creator the admin of that token, we remove this contracts admin rights on that token.
        tokenContract.addPermission(newTokenId, tokenContract.owner(), PERMISSION_BIT_ADMIN);
        tokenContract.removePermission(newTokenId, address(this), PERMISSION_BIT_ADMIN);
    }

    bytes32 constant PREMINT_TYPEHASH = keccak256("delegateCreate(uint256 contractHash,uint256 tokenHash,uint256 quantityToMint)");

    function premintHashData(
        ContractCreationConfig calldata contractConfig,
        TokenCreationConfig calldata tokenConfig,
        uint256 quantityToMint,
        uint256 chainId
    ) public view returns (bytes32 structHash, uint256 contractHash, uint256 tokenHash) {
        contractHash = _contractDataHash(contractConfig);
        tokenHash = _tokenDataHash(contractHash, tokenConfig);
        bytes32 encoded = keccak256(
            abi.encode(PREMINT_TYPEHASH, contractHash, bytes(tokenConfig.tokenURI), tokenConfig.tokenMaxSupply, tokenConfig.tokenSalesConfig, quantityToMint)
        );

        // build the struct hash to be signed
        // here we pass the chain id, allowing the message to be signed for another chain
        structHash = _hashTypedDataV4(encoded, chainId);
    }

    /// returns a unique hash for the contract data, useful to uniquely identify a contract based on creation params
    function _contractDataHash(ContractCreationConfig calldata contractConfig) private pure returns (uint256) {
        return
            uint256(
                keccak256(
                    abi.encode(
                        contractConfig.contractAdmin,
                        _bytesEncode(contractConfig.contractURI),
                        _bytesEncode(contractConfig.contractName),
                        contractConfig.defaultRoyaltyConfiguration
                    )
                )
            );
    }

    /// Return a unique hash for a token creation config, unique within a contract. Used to check if a token has already been created with these params
    function _tokenDataHash(uint256 contractHash, TokenCreationConfig calldata tokenConfig) private pure returns (uint256) {
        return uint256(keccak256(abi.encode(contractHash, bytes(tokenConfig.tokenURI), tokenConfig.tokenMaxSupply, tokenConfig.tokenSalesConfig)));
    }

    function _bytesEncode(string calldata value) private pure returns (bytes32) {
        return keccak256(abi.encode(value));
    }

    function _buildNewSalesConfig(
        address creator,
        PremintFixedPriceSalesConfig calldata _salesConfig
    ) private view returns (ZoraCreatorFixedPriceSaleStrategy.SalesConfig memory) {
        uint64 saleStart = uint64(block.timestamp);
        uint64 saleEnd = _salesConfig.duration == 0 ? type(uint64).max : saleStart + _salesConfig.duration;

        return
            ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                pricePerToken: _salesConfig.pricePerToken,
                saleStart: saleStart,
                saleEnd: saleEnd,
                maxTokensPerAddress: _salesConfig.maxTokensPerAddress,
                fundsRecipient: creator
            });
    }
}
