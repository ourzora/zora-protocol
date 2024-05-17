// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ContractCreationConfig, ContractWithAdditionalAdminsCreationConfig, PremintConfigV2, PremintConfigEncoded, PremintResult, MintArguments} from "../entities/Premint.sol";
import {IGetContractAddress} from "./IGetContractAddress.sol";

interface IZoraCreator1155PremintExecutorV2 is IGetContractAddress {
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
