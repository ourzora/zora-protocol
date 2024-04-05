// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Mock1155} from "./Mock1155.sol";

import {IZoraCreator1155PremintExecutorV2} from "@zoralabs/shared-contracts/interfaces/IZoraCreator1155PremintExecutorV2.sol";
import {EncodedPremintConfig} from "@zoralabs/shared-contracts/premint/PremintEncoding.sol";
import {ContractCreationConfig, PremintConfigV2, MintArguments, PremintResult} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {IZoraMints1155} from "../../src/interfaces/IZoraMints1155.sol";
import {IZoraMintsMinterManager} from "../../src/interfaces/IZoraMintsMinterManager.sol";

contract MockPreminter is IZoraCreator1155PremintExecutorV2 {
    bytes32 constant salt = keccak256(bytes("randomSalt"));

    // we hardcode this for now for testing
    uint256 public predictedTokenId = 2;

    IZoraMintsMinterManager mintsManager;

    function initialize(IZoraMintsMinterManager _mints) public {
        mintsManager = _mints;
    }

    function getCreationCode(ContractCreationConfig memory contractConfig) public view returns (bytes memory) {
        return
            abi.encodePacked(
                type(Mock1155).creationCode,
                abi.encode(mintsManager, contractConfig.contractAdmin, contractConfig.contractURI, contractConfig.contractName)
            );
    }

    function getContractAddress(ContractCreationConfig calldata contractConfig) public view returns (address) {
        return Create2.computeAddress(salt, keccak256(getCreationCode(contractConfig)));
    }

    function getOrCreateContract(ContractCreationConfig calldata contractConfig) private returns (Mock1155 tokenContract, bool isNewContract) {
        address contractAddress = getContractAddress(contractConfig);

        if (contractAddress.code.length == 0) {
            address createdAddress = Create2.deploy(0, salt, getCreationCode(contractConfig));

            if (createdAddress != getContractAddress(contractConfig)) {
                revert("MockPreminter: created address does not match expected address");
            }
        }

        return (Mock1155(contractAddress), false);
    }

    function _doTransfer(uint256[] calldata mintTokenIds, uint256[] calldata mintTokenIdQuantities, address contractAddress) private {
        // transfer mints to itself
        // then transfer mints to the contract
        Mock1155(contractAddress).transferMINTsToSelf(mintTokenIds, mintTokenIdQuantities);
    }

    function premintV2(
        ContractCreationConfig calldata contractConfig,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        MintArguments calldata mintArguments
    ) external payable returns (PremintResult memory result) {
        revert("Not implemented");
    }

    function premintV2WithSignerContract(
        ContractCreationConfig calldata contractConfig,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        MintArguments calldata mintArguments,
        address firstMinter,
        address signerContract
    ) external payable returns (PremintResult memory result) {
        address contractAddress = getContractAddress(contractConfig);

        if (contractAddress.code.length == 0) {
            address createdAddress = Create2.deploy(0, salt, getCreationCode(contractConfig));

            if (createdAddress != getContractAddress(contractConfig)) {
                revert("MockPreminter: created address does not match expected address");
            }
        }

        return PremintResult(contractAddress, predictedTokenId, false);
    }
}
