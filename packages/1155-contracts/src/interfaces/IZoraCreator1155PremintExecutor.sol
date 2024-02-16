// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {PremintEncoding, ZoraCreator1155Attribution, ContractCreationConfig, PremintConfig, PremintConfigV2, TokenCreationConfig, TokenCreationConfigV2} from "../delegation/ZoraCreator1155Attribution.sol";
import {IOwnable2StepUpgradeable} from "../utils/ownable/IOwnable2StepUpgradeable.sol";
import {IZoraCreator1155Factory} from "./IZoraCreator1155Factory.sol";

// this contains functions we have removed, but want to keep around for for testing purposes
interface IRemovedZoraCreator1155PremintExecutorFunctions {
    function premint(
        ContractCreationConfig calldata contractConfig,
        PremintConfig calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        string calldata mintComment
    ) external payable returns (uint256 newTokenId);
}

// interface for legacy v1 of premint executor methods
// maintained in order to not break existing calls
// to legacy api when this api is upgraded
interface ILegacyZoraCreator1155PremintExecutor {
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

    function isAuthorizedToCreatePremint(
        address signer,
        address premintContractConfigContractAdmin,
        address contractAddress
    ) external view returns (bool isAuthorized);
}

interface IZoraCreator1155PremintExecutorV1 {
    function premintV1(
        ContractCreationConfig calldata contractConfig,
        PremintConfig calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        IZoraCreator1155PremintExecutor.MintArguments calldata mintArguments
    ) external payable returns (IZoraCreator1155PremintExecutor.PremintResult memory);
}

interface IZoraCreator1155PremintExecutorV2 {
    function premintV2(
        ContractCreationConfig calldata contractConfig,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        IZoraCreator1155PremintExecutor.MintArguments calldata mintArguments
    ) external payable returns (IZoraCreator1155PremintExecutor.PremintResult memory);

    function premintV2WithSignerContract(
        ContractCreationConfig calldata contractConfig,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        IZoraCreator1155PremintExecutor.MintArguments calldata mintArguments,
        address signerContract
    ) external payable returns (IZoraCreator1155PremintExecutor.PremintResult memory result);
}

interface IZoraCreator1155PremintExecutor is
    ILegacyZoraCreator1155PremintExecutor,
    IZoraCreator1155PremintExecutorV1,
    IZoraCreator1155PremintExecutorV2,
    IOwnable2StepUpgradeable
{
    struct MintArguments {
        address mintRecipient;
        string mintComment;
        /// array of accounts to receive rewards - mintReferral is first argument, and platformReferral is second.  platformReferral isn't supported as of now but will be in a future release.
        address[] mintRewardsRecipients;
    }

    struct PremintResult {
        address contractAddress;
        uint256 tokenId;
        bool createdNewContract;
    }

    event PremintedV2(
        address indexed contractAddress,
        uint256 indexed tokenId,
        bool indexed createdNewContract,
        uint32 uid,
        address minter,
        uint256 quantityMinted
    );

    function zora1155Factory() external view returns (IZoraCreator1155Factory);

    function getContractAddress(ContractCreationConfig calldata contractConfig) external view returns (address);

    function supportedPremintSignatureVersions(address contractAddress) external view returns (string[] memory);

    function mintFee(address contractAddress) external view returns (uint256);
}
