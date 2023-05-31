// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {EIP712Upgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/EIP712Upgradeable.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreator1155Impl} from "../nft/ZoraCreator1155Impl.sol";
import {SharedBaseConstants} from "../shared/SharedBaseConstants.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";

contract Preminter is EIP712Upgradeable {
    bytes32 constant DELEGATE_CREATE_TYPEHASH =
        keccak256(
            "delegateCreate(address creator,string newContractURI,string name, ICreatorRoyaltiesControl.RoyaltyConfiguration defaultRoyaltyConfiguration,bytes[] setupActions,address factory)"
        );

    IZoraCreator1155Factory factory;
    ZoraCreatorFixedPriceSaleStrategy fixedPriceSaleStrategy;

    /// @notice copied from SharedBaseConstants
    uint256 constant CONTRACT_BASE_ID = 0;
    /// @notice This user role allows for only mint actions to be performed.
    /// @dev copied from ZoraCreator1155Impl
    uint256 public constant PERMISSION_BIT_MINTER = 2 ** 2;

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

    struct PremintTokenConfig {
        /// @notice The uri of the token metadata
        string tokenURI;
        /// @notice maxSupply The maximum supply of the token
        uint256 maxSupply;
        /// @notice Token pricing and duration configuration
        PremintFixedPriceSalesConfig fixedPriceSalesConfig;
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
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        PremintTokenConfig calldata tokenConfig
    ) public returns (bytes32) {
        // This code must:
        // 2. Create an erc1155 contract with the given name and uri and the creator as the admin
        // 2. Allow this contract to set fixed price sale strategies on the created erc1155, and mint new tokens, so that in the future this contract can mint new tokens and set their rules
        // 3. Mint a new token, and get the new token id
        // 4. Setup fixed price minting rules for the new token
        // 5. Mint x tokens, as configured, to the executor of this transaction.

        // first validate the signature - the creator must match the signer of the message

        // we need to build the setup actions, that must:
        // grant this contract ability to mint tokens - when a token is minted, this contract is
        // granted admin rights on that token
        bytes[] memory setupActions = new bytes[](2);
        setupActions[0] = abi.encodeWithSelector(IZoraCreator1155.addPermission.selector, CONTRACT_BASE_ID, address(this), PERMISSION_BIT_MINTER);

        // create the contract via the factory.
        address newContractAddresss = factory.createContract(contractURI, contractName, defaultRoyaltyConfiguration, contractAdmin, setupActions);
        IZoraCreator1155 newContract = IZoraCreator1155(newContractAddresss);

        // we then mint a new token, and get its token id
        uint256 newTokenId = newContract.setupNewToken(tokenConfig.tokenURI, tokenConfig.maxSupply);
        // we then set up the sales strategy
        // first we grant the fixed price sale strategy minting capabilities
        newContract.addPermission(newTokenId, address(fixedPriceSaleStrategy), PERMISSION_BIT_MINTER);
        // then we set the sales config
        newContract.callSale(
            newTokenId,
            fixedPriceSaleStrategy,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                newTokenId,
                buildNewSalesConfig(contractAdmin, tokenConfig.fixedPriceSalesConfig)
            )
        );
        // this contract is the admin of that token
        // we make the creator the admin of that token, we remove this contracts admin rights on that token.

        // we mint the initial x tokens for this new token id to the executor.

        bytes32 structHash = keccak256(
            abi.encode(DELEGATE_CREATE_TYPEHASH, contractAdmin, bytes(contractURI), bytes(contractName), defaultRoyaltyConfiguration, setupActions)
        );

        return _hashTypedDataV4(structHash);
    }

    function buildNewSalesConfig(
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
