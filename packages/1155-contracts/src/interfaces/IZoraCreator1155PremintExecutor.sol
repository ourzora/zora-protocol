// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {PremintEncoding, ZoraCreator1155Attribution, ContractCreationConfig, PremintConfig, PremintConfigV2, TokenCreationConfig, TokenCreationConfigV2} from "../delegation/ZoraCreator1155Attribution.sol";
import {IZoraCreator1155Factory} from "./IZoraCreator1155Factory.sol";

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

    function premint(
        ContractCreationConfig calldata contractConfig,
        PremintConfig calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        string calldata mintComment
    ) external payable returns (uint256 newTokenId);
}

interface IZoraCreator1155PremintExecutorV1 {
    function premintV1(
        ContractCreationConfig calldata contractConfig,
        PremintConfig calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        IZoraCreator1155PremintExecutor.MintArguments calldata mintArguments
    ) external payable returns (IZoraCreator1155PremintExecutor.PremintResult memory);

    function isValidSignatureV1(
        address originalContractAdmin,
        address contractAddress,
        PremintConfig calldata premintConfig,
        bytes calldata signature
    ) external view returns (bool isValid, address recoveredSigner);
}

interface IZoraCreator1155PremintExecutorV2 {
    function premintV2(
        ContractCreationConfig calldata contractConfig,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        IZoraCreator1155PremintExecutor.MintArguments calldata mintArguments
    ) external payable returns (IZoraCreator1155PremintExecutor.PremintResult memory);

    function isValidSignatureV2(
        address originalContractAdmin,
        address contractAddress,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature
    ) external view returns (bool isValid, address recoveredSigner);
}

interface IZoraCreator1155PremintExecutor is IZoraCreator1155PremintExecutorV1, IZoraCreator1155PremintExecutorV2 {
    struct MintArguments {
        address mintRecipient;
        string mintComment;
        address mintReferral;
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
}
