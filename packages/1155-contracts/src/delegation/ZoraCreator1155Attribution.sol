// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155Errors} from "../interfaces/IZoraCreator1155Errors.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {ECDSAUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {IERC1271} from "../interfaces/IERC1271.sol";

struct ContractCreationConfig {
    // Creator/admin of the created contract.  Must match the account that signed the message
    address contractAdmin;
    // Metadata URI for the created contract
    string contractURI;
    // Name of the created contract
    string contractName;
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
    // deperecated field; will be ignored.
    uint32 royaltyMintSchedule;
    // RoyaltyBPS for created tokens. The royalty amount in basis points for secondary sales.
    uint32 royaltyBPS;
    // This is the address that will be set on the `royaltyRecipient` for the created token on the 1155 contract,
    // which is the address that receives creator rewards and secondary royalties for the token,
    // and on the `fundsRecipient` on the ZoraCreatorFixedPriceSaleStrategy contract for the token,
    // which is the address that receives paid mint funds for the token.
    address royaltyRecipient;
    // Fixed price minter address
    address fixedPriceMinter;
}

struct PremintConfigV2 {
    // The config for the token to be created
    TokenCreationConfigV2 tokenConfig;
    // Unique id of the token, used to ensure that multiple signatures can't be used to create the same intended token.
    // only one signature per token id, scoped to the contract hash can be executed.
    uint32 uid;
    // Version of this premint, scoped to the uid and contract.  Not used for logic in the contract, but used externally to track the newest version
    uint32 version;
    // If executing this signature results in preventing any signature with this uid from being minted.
    bool deleted;
}

struct TokenCreationConfigV2 {
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
    // RoyaltyBPS for created tokens. The royalty amount in basis points for secondary sales.
    uint32 royaltyBPS;
    // This is the address that will be set on the `royaltyRecipient` for the created token on the 1155 contract,
    // which is the address that receives creator rewards and secondary royalties for the token,
    // and on the `fundsRecipient` on the ZoraCreatorFixedPriceSaleStrategy contract for the token,
    // which is the address that receives paid mint funds for the token.
    address payoutRecipient;
    // Fixed price minter address
    address fixedPriceMinter;
    // create referral
    address createReferral;
}

library ZoraCreator1155Attribution {
    string internal constant NAME = "Preminter";
    bytes32 internal constant HASHED_NAME = keccak256(bytes(NAME));
    string internal constant VERSION_1 = "1";
    bytes32 internal constant HASHED_VERSION_1 = keccak256(bytes(VERSION_1));
    string internal constant VERSION_2 = "2";
    bytes32 internal constant HASHED_VERSION_2 = keccak256(bytes(VERSION_2));

    /**
     * @dev Returns the domain separator for the specified chain.
     */
    function _domainSeparatorV4(uint256 chainId, address verifyingContract, bytes32 hashedName, bytes32 hashedVersion) private pure returns (bytes32) {
        return _buildDomainSeparator(hashedName, hashedVersion, verifyingContract, chainId);
    }

    function _buildDomainSeparator(bytes32 nameHash, bytes32 versionHash, address verifyingContract, uint256 chainId) private pure returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, nameHash, versionHash, chainId, verifyingContract));
    }

    function _hashTypedDataV4(
        bytes32 structHash,
        bytes32 hashedName,
        bytes32 hashedVersion,
        address verifyingContract,
        uint256 chainId
    ) private pure returns (bytes32) {
        return ECDSAUpgradeable.toTypedDataHash(_domainSeparatorV4(chainId, verifyingContract, hashedName, hashedVersion), structHash);
    }

    /// @notice Define magic value to verify smart contract signatures (ERC1271).
    bytes4 internal constant MAGIC_VALUE = bytes4(keccak256("isValidSignature(bytes32,bytes)"));

    function recoverSignerHashed(
        bytes32 hashedPremintConfig,
        bytes calldata signature,
        address erc1155Contract,
        bytes32 signatureVersion,
        uint256 chainId,
        address premintSignerContract
    ) internal view returns (address signatory) {
        // first validate the signature - the creator must match the signer of the message
        bytes32 digest = premintHashedTypeDataV4(
            hashedPremintConfig,
            // here we pass the current contract and chain id, ensuring that the message
            // only works for the current chain and contract id
            erc1155Contract,
            signatureVersion,
            chainId
        );

        if (premintSignerContract != address(0)) {
            // if the smart contract wallet is set, then the signature must be validated by that address
            if (premintSignerContract.code.length == 0) {
                revert IZoraCreator1155Errors.premintSignerContractNotAContract();
            }

            try IERC1271(premintSignerContract).isValidSignature(digest, signature) returns (bytes4 magicValue) {
                if (MAGIC_VALUE == magicValue) {
                    return premintSignerContract;
                }
                revert IZoraCreator1155Errors.InvalidSigner(magicValue);
            } catch {
                revert IZoraCreator1155Errors.premintSignerContractFailedToRecoverSigner();
            }
        } else {
            ECDSAUpgradeable.RecoverError recoverError;
            // if the smart contract signer is not set, then the signature must be from the signer of the message
            (signatory, recoverError) = ECDSAUpgradeable.tryRecover(digest, signature);

            if (recoverError != ECDSAUpgradeable.RecoverError.NoError) {
                revert IZoraCreator1155Errors.InvalidSignature(recoverError);
            }
        }
    }

    /// Gets hash data to sign for a premint.
    /// @param erc1155Contract Contract address that signature is to be verified against
    /// @param chainId Chain id that signature is to be verified on
    function premintHashedTypeDataV4(bytes32 structHash, address erc1155Contract, bytes32 signatureVersion, uint256 chainId) internal pure returns (bytes32) {
        // build the struct hash to be signed
        // here we pass the chain id, allowing the message to be signed for another chain
        return _hashTypedDataV4(structHash, HASHED_NAME, signatureVersion, erc1155Contract, chainId);
    }

    bytes32 constant ATTRIBUTION_DOMAIN_V1 =
        keccak256(
            "CreatorAttribution(TokenCreationConfig tokenConfig,uint32 uid,uint32 version,bool deleted)TokenCreationConfig(string tokenURI,uint256 maxSupply,uint64 maxTokensPerAddress,uint96 pricePerToken,uint64 mintStart,uint64 mintDuration,uint32 royaltyMintSchedule,uint32 royaltyBPS,address royaltyRecipient,address fixedPriceMinter)"
        );

    function hashPremint(PremintConfig memory premintConfig) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(ATTRIBUTION_DOMAIN_V1, _hashToken(premintConfig.tokenConfig), premintConfig.uid, premintConfig.version, premintConfig.deleted)
            );
    }

    bytes32 constant ATTRIBUTION_DOMAIN_V2 =
        keccak256(
            "CreatorAttribution(TokenCreationConfig tokenConfig,uint32 uid,uint32 version,bool deleted)TokenCreationConfig(string tokenURI,uint256 maxSupply,uint64 maxTokensPerAddress,uint96 pricePerToken,uint64 mintStart,uint64 mintDuration,uint32 royaltyBPS,address payoutRecipient,address fixedPriceMinter,address createReferral)"
        );

    function hashPremint(PremintConfigV2 memory premintConfig) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(ATTRIBUTION_DOMAIN_V2, _hashToken(premintConfig.tokenConfig), premintConfig.uid, premintConfig.version, premintConfig.deleted)
            );
    }

    bytes32 constant TOKEN_DOMAIN_V1 =
        keccak256(
            "TokenCreationConfig(string tokenURI,uint256 maxSupply,uint64 maxTokensPerAddress,uint96 pricePerToken,uint64 mintStart,uint64 mintDuration,uint32 royaltyMintSchedule,uint32 royaltyBPS,address royaltyRecipient,address fixedPriceMinter)"
        );

    function _hashToken(TokenCreationConfig memory tokenConfig) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    TOKEN_DOMAIN_V1,
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

    bytes32 constant TOKEN_DOMAIN_V2 =
        keccak256(
            "TokenCreationConfig(string tokenURI,uint256 maxSupply,uint64 maxTokensPerAddress,uint96 pricePerToken,uint64 mintStart,uint64 mintDuration,uint32 royaltyBPS,address payoutRecipient,address fixedPriceMinter,address createReferral)"
        );

    function _hashToken(TokenCreationConfigV2 memory tokenConfig) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    TOKEN_DOMAIN_V2,
                    _stringHash(tokenConfig.tokenURI),
                    tokenConfig.maxSupply,
                    tokenConfig.maxTokensPerAddress,
                    tokenConfig.pricePerToken,
                    tokenConfig.mintStart,
                    tokenConfig.mintDuration,
                    tokenConfig.royaltyBPS,
                    tokenConfig.payoutRecipient,
                    tokenConfig.fixedPriceMinter,
                    tokenConfig.createReferral
                )
            );
    }

    bytes32 internal constant TYPE_HASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function _stringHash(string memory value) private pure returns (bytes32) {
        return keccak256(bytes(value));
    }

    /// @notice copied from SharedBaseConstants
    uint256 constant CONTRACT_BASE_ID = 0;
    /// @dev copied from ZoraCreator1155Impl
    uint256 constant PERMISSION_BIT_MINTER = 2 ** 2;

    function isAuthorizedToCreatePremint(
        address signer,
        address premintContractConfigContractAdmin,
        address contractAddress
    ) internal view returns (bool authorized) {
        // if contract hasn't been created, signer must be the contract admin on the premint config
        if (contractAddress.code.length == 0) {
            return signer == premintContractConfigContractAdmin;
        } else {
            // if contract has been created, signer must have mint new token permission
            authorized = IZoraCreator1155(contractAddress).isAdminOrRole(signer, CONTRACT_BASE_ID, PERMISSION_BIT_MINTER);
        }
    }
}

/// @notice Utility library to setup tokens created via premint.  Functions exposed as external to not increase contract size in calling contract.
/// @author oveddan
library PremintTokenSetup {
    uint256 constant PERMISSION_BIT_MINTER = 2 ** 2;

    /// @notice Build token setup actions for a v2 preminted token
    function makeSetupNewTokenCalls(uint256 newTokenId, TokenCreationConfigV2 memory tokenConfig) internal view returns (bytes[] memory calls) {
        return
            _buildCalls({
                newTokenId: newTokenId,
                fixedPriceMinterAddress: tokenConfig.fixedPriceMinter,
                pricePerToken: tokenConfig.pricePerToken,
                maxTokensPerAddress: tokenConfig.maxTokensPerAddress,
                mintDuration: tokenConfig.mintDuration,
                royaltyBPS: tokenConfig.royaltyBPS,
                payoutRecipient: tokenConfig.payoutRecipient
            });
    }

    /// @notice Build token setup actions for a v1 preminted token
    function makeSetupNewTokenCalls(uint256 newTokenId, TokenCreationConfig memory tokenConfig) internal view returns (bytes[] memory calls) {
        return
            _buildCalls({
                newTokenId: newTokenId,
                fixedPriceMinterAddress: tokenConfig.fixedPriceMinter,
                pricePerToken: tokenConfig.pricePerToken,
                maxTokensPerAddress: tokenConfig.maxTokensPerAddress,
                mintDuration: tokenConfig.mintDuration,
                royaltyBPS: tokenConfig.royaltyBPS,
                payoutRecipient: tokenConfig.royaltyRecipient
            });
    }

    function _buildCalls(
        uint256 newTokenId,
        address fixedPriceMinterAddress,
        uint96 pricePerToken,
        uint64 maxTokensPerAddress,
        uint64 mintDuration,
        uint32 royaltyBPS,
        address payoutRecipient
    ) private view returns (bytes[] memory calls) {
        calls = new bytes[](3);

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
                _buildNewSalesConfig(pricePerToken, maxTokensPerAddress, mintDuration, payoutRecipient)
            )
        );

        // set the royalty config on that token:
        calls[2] = abi.encodeWithSelector(
            IZoraCreator1155.updateRoyaltiesForToken.selector,
            newTokenId,
            ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyBPS: royaltyBPS, royaltyRecipient: payoutRecipient, royaltyMintSchedule: 0})
        );
    }

    function _buildNewSalesConfig(
        uint96 pricePerToken,
        uint64 maxTokensPerAddress,
        uint64 duration,
        address payoutRecipient
    ) private view returns (ZoraCreatorFixedPriceSaleStrategy.SalesConfig memory) {
        uint64 saleStart = uint64(block.timestamp);
        uint64 saleEnd = duration == 0 ? type(uint64).max : saleStart + duration;

        return
            ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                pricePerToken: pricePerToken,
                saleStart: saleStart,
                saleEnd: saleEnd,
                maxTokensPerAddress: maxTokensPerAddress,
                fundsRecipient: payoutRecipient
            });
    }
}

library PremintEncoding {
    function encodePremintV1(PremintConfig memory premintConfig) internal pure returns (bytes memory encodedPremintConfig, bytes32 hashedVersion) {
        return (abi.encode(premintConfig), ZoraCreator1155Attribution.HASHED_VERSION_1);
    }

    function encodePremintV2(PremintConfigV2 memory premintConfig) internal pure returns (bytes memory encodedPremintConfig, bytes32 hashedVersion) {
        return (abi.encode(premintConfig), ZoraCreator1155Attribution.HASHED_VERSION_2);
    }
}

struct DecodedCreatorAttribution {
    bytes32 structHash;
    string domainName;
    string version;
    address creator;
    bytes signature;
}

struct DelegatedTokenSetup {
    DecodedCreatorAttribution attribution;
    uint32 uid;
    string tokenURI;
    uint256 maxSupply;
    address createReferral;
}

/// @notice Utility library to decode and recover delegated token setup data from a signature.
/// Function called by the erc1155 contract is marked external to reduce contract size in calling contract.
library DelegatedTokenCreation {
    /// @notice Decode and recover delegated token setup data from a signature. Works with multiple versions of
    /// a signature.  Takes an abi encoded premint config, version of the encoded premint config, and a signature,
    /// decodes the config, and recoveres the signer of the config.  Based on the premint config, builds
    /// setup actions for the token to be created.
    /// @param premintConfigEncoded The abi encoded premint config
    /// @param premintVersion The version of the premint config
    /// @param signature The signature of the premint config
    /// @param tokenContract The address of the token contract that the premint config is for
    /// @param newTokenId The id of the token to be created
    function decodeAndRecoverDelegatedTokenSetup(
        bytes memory premintConfigEncoded,
        bytes32 premintVersion,
        bytes calldata signature,
        address tokenContract,
        uint256 newTokenId,
        address premintSignerContract
    ) external view returns (DelegatedTokenSetup memory params, DecodedCreatorAttribution memory creatorAttribution, bytes[] memory tokenSetupActions) {
        // based on version of encoded premint config, decode corresponding premint config,
        // and then recover signer from the signature, and then build token setup actions based
        // on the decoded premint config.
        if (premintVersion == ZoraCreator1155Attribution.HASHED_VERSION_1) {
            PremintConfig memory premintConfig = abi.decode(premintConfigEncoded, (PremintConfig));

            creatorAttribution = recoverCreatorAttribution(
                ZoraCreator1155Attribution.VERSION_1,
                ZoraCreator1155Attribution.hashPremint(premintConfig),
                tokenContract,
                signature,
                premintSignerContract
            );

            (params, tokenSetupActions) = _recoverDelegatedTokenSetup(premintConfig, newTokenId);
        } else {
            PremintConfigV2 memory premintConfig = abi.decode(premintConfigEncoded, (PremintConfigV2));

            creatorAttribution = recoverCreatorAttribution(
                ZoraCreator1155Attribution.VERSION_2,
                ZoraCreator1155Attribution.hashPremint(premintConfig),
                tokenContract,
                signature,
                premintSignerContract
            );

            (params, tokenSetupActions) = _recoverDelegatedTokenSetup(premintConfig, newTokenId);
        }
    }

    function supportedPremintSignatureVersions() external pure returns (string[] memory versions) {
        return _supportedPremintSignatureVersions();
    }

    function _supportedPremintSignatureVersions() internal pure returns (string[] memory versions) {
        versions = new string[](2);
        versions[0] = ZoraCreator1155Attribution.VERSION_1;
        versions[1] = ZoraCreator1155Attribution.VERSION_2;
    }

    function recoverCreatorAttribution(
        string memory version,
        bytes32 structHash,
        address tokenContract,
        bytes calldata signature,
        address premintSignerContract
    ) internal view returns (DecodedCreatorAttribution memory attribution) {
        attribution.structHash = structHash;
        attribution.version = version;

        attribution.creator = ZoraCreator1155Attribution.recoverSignerHashed(
            structHash,
            signature,
            tokenContract,
            keccak256(bytes(version)),
            block.chainid,
            premintSignerContract
        );

        attribution.signature = signature;
        attribution.domainName = ZoraCreator1155Attribution.NAME;
    }

    function _recoverDelegatedTokenSetup(
        PremintConfigV2 memory premintConfig,
        uint256 nextTokenId
    ) private view returns (DelegatedTokenSetup memory params, bytes[] memory tokenSetupActions) {
        validatePremint(premintConfig.tokenConfig.mintStart, premintConfig.deleted);

        params.uid = premintConfig.uid;

        tokenSetupActions = PremintTokenSetup.makeSetupNewTokenCalls({newTokenId: nextTokenId, tokenConfig: premintConfig.tokenConfig});

        params.tokenURI = premintConfig.tokenConfig.tokenURI;
        params.maxSupply = premintConfig.tokenConfig.maxSupply;
        params.createReferral = premintConfig.tokenConfig.createReferral;
    }

    function _recoverDelegatedTokenSetup(
        PremintConfig memory premintConfig,
        uint256 nextTokenId
    ) private view returns (DelegatedTokenSetup memory params, bytes[] memory tokenSetupActions) {
        validatePremint(premintConfig.tokenConfig.mintStart, premintConfig.deleted);

        params.uid = premintConfig.uid;

        tokenSetupActions = PremintTokenSetup.makeSetupNewTokenCalls(nextTokenId, premintConfig.tokenConfig);

        params.tokenURI = premintConfig.tokenConfig.tokenURI;
        params.maxSupply = premintConfig.tokenConfig.maxSupply;
    }

    function validatePremint(uint64 mintStart, bool deleted) private view {
        if (mintStart != 0 && mintStart > block.timestamp) {
            // if the mint start is in the future, then revert
            revert IZoraCreator1155Errors.MintNotYetStarted();
        }
        if (deleted) {
            // if the signature says to be deleted, then dont execute any further minting logic;
            // return 0
            revert IZoraCreator1155Errors.PremintDeleted();
        }
    }
}
