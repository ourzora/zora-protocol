// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ContractCreationConfig, PremintConfigV2, PremintResult, MintArguments} from "../entities/Premint.sol";
import {IGetContractAddress} from "./IGetContractAddress.sol";

interface IZoraCreator1155PremintExecutorV2 is IGetContractAddress {
    function premintV2(
        ContractCreationConfig calldata contractConfig,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        MintArguments calldata mintArguments
    ) external payable returns (PremintResult memory);

    function premintV2WithSignerContract(
        ContractCreationConfig calldata contractConfig,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        MintArguments calldata mintArguments,
        address firstMinter,
        address signerContract
    ) external payable returns (PremintResult memory result);
}
