// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IZoraCreator1155Errors} from "@zoralabs/shared-contracts/interfaces/errors/IZoraCreator1155Errors.sol";
import {IMinter1155} from "@zoralabs/shared-contracts/interfaces/IMinter1155.sol";
import {IMintWithMints} from "./IMintWithMints.sol";
import {PremintResult} from "@zoralabs/shared-contracts/entities/Premint.sol";

import {ContractCreationConfig, PremintConfigV2, MintArguments, PremintResult} from "@zoralabs/shared-contracts/entities/Premint.sol";

interface ICollectWithZoraMints is IZoraCreator1155Errors {
    event Collected(uint256[] indexed tokenIds, uint256[] quantities, address indexed zoraCreator1155Contract, uint256 indexed zoraCreator1155TokenId);
    event MintComment(address indexed sender, address indexed tokenContract, uint256 indexed tokenId, uint256 quantity, string comment);

    /**
     * @dev Occurs when mintWithMints is not supported on an 1155 contract.
     */
    error MintWithMintsNotSupportedOnContract();

    error NoTokensTransferred();

    error NotZoraMints1155();

    error NotSelfCall();

    error ERC1155BatchReceivedCallFailed();

    error UnknownUserAction(bytes4 selector);

    struct CollectMintArguments {
        address[] mintRewardsRecipients;
        bytes minterArguments;
        string mintComment;
    }

    function collect(
        IMintWithMints zoraCreator1155Contract,
        IMinter1155 minter,
        uint256 zoraCreator1155TokenId,
        CollectMintArguments calldata collectMintArguments
    ) external payable;

    function collectPremintV2(
        ContractCreationConfig calldata contractConfig,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature,
        MintArguments calldata mintArguments,
        address signerContract
    ) external payable returns (PremintResult memory);

    function callWithTransferTokens(
        address callFrom,
        uint256[] calldata tokenIds,
        uint256[] calldata quantities,
        bytes calldata call
    ) external payable returns (bool success, bytes memory result);
}
