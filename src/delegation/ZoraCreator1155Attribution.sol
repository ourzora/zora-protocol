// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {ECDSAUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";

struct ContractCreationConfig {
    // Creator/admin of the created contract.  Must match the account that signed the message
    address contractAdmin;
    // Metadata URI for the created contract
    string contractURI;
    // Name of the created contract
    string contractName;
}

struct TokenCreationConfig {
    // Metadata URI for the created token
    string tokenURI;
    // Max supply of the created token
    uint256 maxSupply;
    // Max tokens that can be minted for an address, 0 if unlimited
    uint64 maxTokensPerAddress;
    // Price per token in eth wei. 0 for a free mint.
    uint96 pricePerToken;
    // The start time of the mint, 0 for immediate.  Prevents signatures from being used until the start time.
    uint64 mintStart;
    // The duration of the mint, starting from the first mint of this token. 0 for infinite
    uint64 mintDuration;
    // RoyaltyMintSchedule for created tokens. Every nth token will go to the royalty recipient.
    uint32 royaltyMintSchedule;
    // RoyaltyBPS for created tokens. The royalty amount in basis points for secondary sales.
    uint32 royaltyBPS;
    // RoyaltyRecipient for created tokens. The address that will receive the royalty payments.
    address royaltyRecipient;
    // Fixed price minter address
    address fixedPriceMinter;
}

struct PremintConfig {
    // The config for the token to be created
    TokenCreationConfig tokenConfig;
    // Unique id of the token, used to ensure that multiple signatures can't be used to create the same intended token.
    // only one signature per token id, scoped to the contract hash can be executed.
    uint32 uid;
    // Version of this premint, scoped to the uid and contract.  Not used for logic in the contract, but used externally to track the newest version
    uint32 version;
    // If executing this signature results in preventing any signature with this uid from being minted.
    bool deleted;
}

/// @title Library for enables a creator to signal intent to create a Zora erc1155 contract or new token on that
/// contract by signing a transaction but not paying gas, and have a third party/collector pay the gas
/// by executing the transaction.  Functions are exposed as external to allow contracts to import this lib and not increase their
/// size.
/// @author @oveddan
library ZoraCreator1155Attribution {
    /* start eip712 functionality */
    string internal constant NAME = "Preminter";
    string internal constant VERSION = "1";
    bytes32 internal constant HASHED_NAME = keccak256(bytes(NAME));
    bytes32 internal constant HASHED_VERSION = keccak256(bytes(VERSION));
    bytes32 internal constant TYPE_HASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /**
     * @dev Returns the domain separator for the specified chain.
     */
    function _domainSeparatorV4(uint256 chainId, address verifyingContract) internal pure returns (bytes32) {
        return _buildDomainSeparator(HASHED_NAME, HASHED_VERSION, verifyingContract, chainId);
    }

    function _buildDomainSeparator(bytes32 nameHash, bytes32 versionHash, address verifyingContract, uint256 chainId) private pure returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, nameHash, versionHash, chainId, verifyingContract));
    }

    function _hashTypedDataV4(bytes32 structHash, address verifyingContract, uint256 chainId) private pure returns (bytes32) {
        return ECDSAUpgradeable.toTypedDataHash(_domainSeparatorV4(chainId, verifyingContract), structHash);
    }

    /* end eip712 functionality */

    function recoverSigner(
        PremintConfig calldata premintConfig,
        bytes calldata signature,
        address erc1155Contract,
        uint256 chainId
    ) internal pure returns (address signatory) {
        // first validate the signature - the creator must match the signer of the message
        return recoverSignerHashed(hashPremint(premintConfig), signature, erc1155Contract, chainId);
    }

    function recoverSignerHashed(
        bytes32 hashedPremintConfig,
        bytes calldata signature,
        address erc1155Contract,
        uint256 chainId
    ) public pure returns (address signatory) {
        // first validate the signature - the creator must match the signer of the message
        bytes32 digest = _hashTypedDataV4(
            hashedPremintConfig,
            // here we pass the current contract and chain id, ensuring that the message
            // only works for the current chain and contract id
            erc1155Contract,
            chainId
        );

        signatory = ECDSAUpgradeable.recover(digest, signature);
    }

    /// Gets hash data to sign for a premint.  Allows specifying a different chain id and contract address so that the signature
    /// can be verified on a different chain.
    /// @param erc1155Contract Contract address that signature is to be verified against
    /// @param chainId Chain id that signature is to be verified on
    function premintHashedTypeDataV4(PremintConfig calldata premintConfig, address erc1155Contract, uint256 chainId) external pure returns (bytes32) {
        // build the struct hash to be signed
        // here we pass the chain id, allowing the message to be signed for another chain
        return _hashTypedDataV4(hashPremint(premintConfig), erc1155Contract, chainId);
    }

    bytes32 constant ATTRIBUTION_DOMAIN =
        keccak256(
            "CreatorAttribution(TokenCreationConfig tokenConfig,uint32 uid,uint32 version,bool deleted)TokenCreationConfig(string tokenURI,uint256 maxSupply,uint64 maxTokensPerAddress,uint96 pricePerToken,uint64 mintStart,uint64 mintDuration,uint32 royaltyMintSchedule,uint32 royaltyBPS,address royaltyRecipient,address fixedPriceMinter)"
        );

    function hashPremint(PremintConfig calldata premintConfig) public pure returns (bytes32) {
        return
            keccak256(abi.encode(ATTRIBUTION_DOMAIN, _hashToken(premintConfig.tokenConfig), premintConfig.uid, premintConfig.version, premintConfig.deleted));
    }

    bytes32 constant TOKEN_DOMAIN =
        keccak256(
            "TokenCreationConfig(string tokenURI,uint256 maxSupply,uint64 maxTokensPerAddress,uint96 pricePerToken,uint64 mintStart,uint64 mintDuration,uint32 royaltyMintSchedule,uint32 royaltyBPS,address royaltyRecipient,address fixedPriceMinter)"
        );

    function _hashToken(TokenCreationConfig calldata tokenConfig) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    TOKEN_DOMAIN,
                    _stringHash(tokenConfig.tokenURI),
                    tokenConfig.maxSupply,
                    tokenConfig.maxTokensPerAddress,
                    tokenConfig.pricePerToken,
                    tokenConfig.mintStart,
                    tokenConfig.mintDuration,
                    tokenConfig.royaltyMintSchedule,
                    tokenConfig.royaltyBPS,
                    tokenConfig.royaltyRecipient,
                    tokenConfig.fixedPriceMinter
                )
            );
    }

    function _stringHash(string calldata value) private pure returns (bytes32) {
        return keccak256(bytes(value));
    }
}

/// @notice Utilitiy library to setup tokens created via premint.  Functions exposed as external to not increase contract size in calling contract.
/// @author oveddan
library PremintTokenSetup {
    uint256 constant PERMISSION_BIT_MINTER = 2 ** 2;

    function makeSetupNewTokenCalls(
        uint256 newTokenId,
        address contractAdmin,
        TokenCreationConfig calldata tokenConfig
    ) external view returns (bytes[] memory calls) {
        calls = new bytes[](3);

        address fixedPriceMinterAddress = tokenConfig.fixedPriceMinter;
        // build array of the calls to make
        // get setup actions and invoke them
        // set up the sales strategy
        // first, grant the fixed price sale strategy minting capabilities on the token
        // tokenContract.addPermission(newTokenId, address(fixedPriceMinter), PERMISSION_BIT_MINTER);
        calls[0] = abi.encodeWithSelector(IZoraCreator1155.addPermission.selector, newTokenId, fixedPriceMinterAddress, PERMISSION_BIT_MINTER);

        // set the sales config on that token
        calls[1] = abi.encodeWithSelector(
            IZoraCreator1155.callSale.selector,
            newTokenId,
            IMinter1155(fixedPriceMinterAddress),
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                newTokenId,
                _buildNewSalesConfig(contractAdmin, tokenConfig.pricePerToken, tokenConfig.maxTokensPerAddress, tokenConfig.mintDuration)
            )
        );

        // set the royalty config on that token:
        calls[2] = abi.encodeWithSelector(
            IZoraCreator1155.updateRoyaltiesForToken.selector,
            newTokenId,
            ICreatorRoyaltiesControl.RoyaltyConfiguration({
                royaltyBPS: tokenConfig.royaltyBPS,
                royaltyRecipient: tokenConfig.royaltyRecipient,
                royaltyMintSchedule: tokenConfig.royaltyMintSchedule
            })
        );
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
