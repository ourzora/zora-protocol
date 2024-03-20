// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ContractCreationConfig} from "../entities/Premint.sol";

interface IGetContractAddress {
    function getContractAddress(ContractCreationConfig calldata contractConfig) external view returns (address);
}
