// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {EIP712Upgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSAUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreator1155Impl} from "../nft/ZoraCreator1155Impl.sol";
import {SharedBaseConstants} from "../shared/SharedBaseConstants.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";

contract Preminter is EIP712Upgradeable {
    bytes32 constant PREMINT_TYPEHASH =
        keccak256(
            "delegateCreate(address contractAdmin,bytes contractURI,bytes contractName,ICreatorRoyaltiesControl.RoyaltyConfiguration defaultRoyaltyConfiguration,bytes tokenURI,uint256 tokenMaxSupply,PremintFixedPriceSalesConfig tokenSalesConfig,uint256 quantityToMint)"
        );

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
    mapping(address => mapping(uint64 => bool)) nonces;

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

    // same signature should work whether or not there is an existing contract
    // so it is unaware of order, it just takes the token uri and creates the next token with it
    // this could include creating the contract.

    // do we need a deadline? open q

    // forward payable

    function premint(
        address payable contractAdmin,
        string calldata contractURI,
        string calldata contractName,
        ICreatorRoyaltiesControl.RoyaltyConfiguration calldata defaultRoyaltyConfiguration,
        string calldata tokenURI,
        uint256 tokenMaxSupply,
        PremintFixedPriceSalesConfig calldata tokenSalesConfig,
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
        bytes32 digest = premintHashData(
            contractAdmin,
            contractURI,
            contractName,
            defaultRoyaltyConfiguration,
            tokenURI,
            tokenMaxSupply,
            tokenSalesConfig,
            quantityToMint
        );

        address signatory = ECDSAUpgradeable.recover(digest, signature);
        if (signatory != contractAdmin) revert("Invalid signature");

        (IZoraCreator1155 tokenContract, uint256 contractHash) = _getOrCreateContract(contractAdmin, contractURI, contractName, defaultRoyaltyConfiguration);

        _setupNewTokenAndSale(tokenContract, contractAdmin, tokenURI, tokenMaxSupply, tokenSalesConfig);

        // we mint the initial x tokens for this new token id to the executor.
        address tokenRecipient = msg.sender;
        tokenContract.mint{value: msg.value}(fixedPriceSaleStrategy, newTokenId, quantityToMint, abi.encode(tokenRecipient, ""));
    }

    function _getOrCreateContract(
        address payable contractAdmin,
        string calldata contractURI,
        string calldata contractName,
        ICreatorRoyaltiesControl.RoyaltyConfiguration calldata defaultRoyaltyConfiguration
    ) private returns (IZoraCreator1155 tokenContract, uint256 contractHash) {
        // get unique hash based on contract params
        contractHash = _contractDataHash(contractAdmin, contractURI, contractName, defaultRoyaltyConfiguration);

        address contractAddress = contractAddresses[contractHash];
        // if address already exists for hash, return it
        if (contractAddress != address(0)) {
            tokenContract = IZoraCreator1155(contractAddress);
        } else {
            // otherwise, create the contract and update the created contracts
            tokenContract = _createContract(contractAdmin, contractURI, contractName, defaultRoyaltyConfiguration);
            contractAddresses[contractHash] = address(tokenContract);
        }
    }

    function _createContract(
        address payable contractAdmin,
        string calldata contractURI,
        string calldata contractName,
        ICreatorRoyaltiesControl.RoyaltyConfiguration calldata defaultRoyaltyConfiguration
    ) private returns (IZoraCreator1155 tokenContract) {
        // we need to build the setup actions, that must:
        // grant this contract ability to mint tokens - when a token is minted, this contract is
        // granted admin rights on that token
        bytes[] memory setupActions = new bytes[](2);
        setupActions[0] = abi.encodeWithSelector(IZoraCreator1155.addPermission.selector, CONTRACT_BASE_ID, address(this), PERMISSION_BIT_MINTER);

        // create the contract via the factory.
        address newContractAddresss = factory.createContract(contractURI, contractName, defaultRoyaltyConfiguration, contractAdmin, setupActions);
        tokenContract = IZoraCreator1155(newContractAddresss);
    }

    function _contractDataHash(
        address contractAdmin,
        string calldata contractURI,
        string calldata contractName,
        ICreatorRoyaltiesControl.RoyaltyConfiguration calldata defaultRoyaltyConfiguration
    ) private pure returns (uint256) {
        return uint256(keccak256(abi.encode(contractAdmin, _bytesEncode(contractURI), _bytesEncode(contractName), defaultRoyaltyConfiguration)));
    }

    function _bytesEncode(string calldata value) private pure returns (bytes32) {
        return keccak256(abi.encode(value));
    }

    function _setupNewTokenAndSale(
        IZoraCreator1155 tokenContract,
        address contractAdmin,
        string calldata tokenURI,
        uint256 tokenMaxSupply,
        PremintFixedPriceSalesConfig calldata tokenSalesConfig
    ) private returns (uint256 newTokenId) {
        // we then mint a new token, and get its token id
        newTokenId = tokenContract.setupNewToken(tokenURI, tokenMaxSupply);
        // we then set up the sales strategy
        // first we grant the fixed price sale strategy minting capabilities
        tokenContract.addPermission(newTokenId, address(fixedPriceSaleStrategy), PERMISSION_BIT_MINTER);
        // then we set the sales config
        tokenContract.callSale(
            newTokenId,
            fixedPriceSaleStrategy,
            abi.encodeWithSelector(ZoraCreatorFixedPriceSaleStrategy.setSale.selector, newTokenId, _buildNewSalesConfig(contractAdmin, tokenSalesConfig))
        );
        // this contract is the admin of that token - lets make the contract
        // we make the creator the admin of that token, we remove this contracts admin rights on that token.
        tokenContract.addPermission(newTokenId, tokenContract.owner(), PERMISSION_BIT_ADMIN);
        tokenContract.removePermission(newTokenId, address(this), PERMISSION_BIT_ADMIN);
    }

    function premintHashData(
        address contractAdmin,
        string calldata contractURI,
        string calldata contractName,
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        string calldata tokenURI,
        uint256 tokenMaxSupply,
        PremintFixedPriceSalesConfig calldata fixedPriceSalesConfig,
        uint256 quantityToMint
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                PREMINT_TYPEHASH,
                contractAdmin,
                bytes(contractURI),
                bytes(contractName),
                defaultRoyaltyConfiguration,
                bytes(tokenURI),
                tokenMaxSupply,
                fixedPriceSalesConfig,
                quantityToMint
            )
        );

        return _hashTypedDataV4(structHash);
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
