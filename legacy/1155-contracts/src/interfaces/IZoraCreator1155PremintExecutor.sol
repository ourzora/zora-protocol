// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {PremintEncoding, ZoraCreator1155Attribution, ContractCreationConfig, PremintConfig, PremintConfigV2, TokenCreationConfig, TokenCreationConfigV2} from "../delegation/ZoraCreator1155Attribution.sol";
import {IOwnable2StepUpgradeable} from "../utils/ownable/IOwnable2StepUpgradeable.sol";
import {IZoraCreator1155Factory} from "./IZoraCreator1155Factory.sol";
import {IGetContractAddress} from "@zoralabs/shared-contracts/interfaces/IGetContractAddress.sol";
import {MintArguments, PremintResult} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {IZoraCreator1155PremintExecutorV2} from "@zoralabs/shared-contracts/interfaces/IZoraCreator1155PremintExecutorV2.sol";

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

    function premintV1(
        ContractCreationConfig calldata contractConfig,
        PremintConfig calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        MintArguments calldata mintArguments
    ) external payable returns (PremintResult memory);

    function premintV2(
        ContractCreationConfig calldata contractConfig,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        MintArguments calldata mintArguments
    ) external payable returns (PremintResult memory);
}

interface IZoraCreator1155PremintExecutor is ILegacyZoraCreator1155PremintExecutor, IGetContractAddress, IOwnable2StepUpgradeable {
    event PremintedV2(
        address indexed contractAddress,
        uint256 indexed tokenId,
        bool indexed createdNewContract,
        uint32 uid,
        address minter,
        uint256 quantityMinted
    );

    function zora1155Factory() external view returns (IZoraCreator1155Factory);

    function supportedPremintSignatureVersions(address contractAddress) external view returns (string[] memory);

    function mintFee(address contractAddress) external view returns (uint256);
}
