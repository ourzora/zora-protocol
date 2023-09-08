// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {PremintConfig, ZoraCreator1155Attribution} from "./ZoraCreator1155Attribution.sol";

interface IZoraCreator1155DelegatedCreation {
    function validateAndHashPremint(PremintConfig calldata premintConfig) external view returns (bytes32);

    function recoverSignerHashed(
        bytes32 hashedPremintConfig,
        bytes calldata signature,
        address erc1155Contract,
        uint256 chainId
    ) external pure returns (address signatory);

    function HASHED_NAME() external returns (bytes32);

    function HASHED_VERSION() external returns (bytes32);
}

contract ZoraCreator1155DelegatedCreation is IZoraCreator1155DelegatedCreation {
    function validateAndHashPremint(PremintConfig calldata premintConfig) external view returns (bytes32) {
        return ZoraCreator1155Attribution.validateAndHashPremint(premintConfig);
    }

    function recoverSignerHashed(
        bytes32 hashedPremintConfig,
        bytes calldata signature,
        address erc1155Contract,
        uint256 chainId
    ) external pure returns (address signatory) {
        return ZoraCreator1155Attribution.recoverSignerHashed(hashedPremintConfig, signature, erc1155Contract, chainId);
    }

    function HASHED_NAME() external pure override returns (bytes32) {
        return ZoraCreator1155Attribution.HASHED_NAME;
    }

    function HASHED_VERSION() external pure override returns (bytes32) {
        return ZoraCreator1155Attribution.HASHED_VERSION;
    }
}
