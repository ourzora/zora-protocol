// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Mock1155} from "./Mock1155.sol";

import {IZoraCreator1155PremintExecutorAllVersions} from "@zoralabs/shared-contracts/interfaces/IZoraCreator1155PremintExecutorAllVersions.sol";
import {ContractCreationConfig, ContractWithAdditionalAdminsCreationConfig, PremintConfigV2, MintArguments, PremintResult, PremintConfigEncoded} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {IZoraMints1155} from "../../src/interfaces/IZoraMints1155.sol";
import {IZoraMintsMinterManager} from "../../src/interfaces/IZoraMintsMinterManager.sol";

contract MockPreminter is IZoraCreator1155PremintExecutorAllVersions {
    bytes32 constant salt = keccak256(bytes("randomSalt"));

    // we hardcode this for now for testing
    uint256 public predictedTokenId = 2;

    IZoraMintsMinterManager mintsManager;

    function initialize(IZoraMintsMinterManager _mints) public {
        mintsManager = _mints;
    }

    function getCreationCode(ContractWithAdditionalAdminsCreationConfig memory contractConfig) public view returns (bytes memory) {
        return
            abi.encodePacked(
                type(Mock1155).creationCode,
                abi.encode(mintsManager, contractConfig.contractAdmin, contractConfig.contractURI, contractConfig.contractName, contractConfig.additionalAdmins)
            );
    }

    function getContractAddress(ContractCreationConfig calldata) public view returns (address) {
        revert("Not Implemented");
    }

    function getContractWithAdditionalAdminsAddress(ContractWithAdditionalAdminsCreationConfig calldata contractConfig) public view returns (address) {
        return Create2.computeAddress(salt, keccak256(getCreationCode(contractConfig)));
    }

    function _doTransfer(uint256[] calldata mintTokenIds, uint256[] calldata mintTokenIdQuantities, address contractAddress) private {
        // transfer mints to itself
        // then transfer mints to the contract
        Mock1155(contractAddress).transferMINTsToSelf(mintTokenIds, mintTokenIdQuantities);
    }

    function getOrCreateContract(ContractWithAdditionalAdminsCreationConfig calldata contractConfig) public returns (address) {
        address contractAddress = getContractWithAdditionalAdminsAddress(contractConfig);

        if (contractAddress.code.length == 0) {
            address createdAddress = Create2.deploy(0, salt, getCreationCode(contractConfig));

            if (createdAddress != contractAddress) {
                revert("MockPreminter: created address does not match expected address");
            }
        }

        return contractAddress;
    }

    function premint(
        ContractWithAdditionalAdminsCreationConfig calldata contractConfig,
        address tokenContract,
        PremintConfigEncoded calldata,
        bytes calldata signature,
        uint256 quantityToMint,
        MintArguments calldata mintArguments,
        address firstMinter,
        address signerContract
    ) external payable returns (PremintResult memory) {
        address contractAddress = tokenContract == address(0) ? getOrCreateContract(contractConfig) : tokenContract;

        return PremintResult(contractAddress, predictedTokenId, false);
    }

    function premintV2WithSignerContract(
        ContractCreationConfig calldata contractConfig,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature,
        uint256 quantityToMint,
        MintArguments calldata mintArguments,
        address firstMinter,
        address signerContract
    ) external payable returns (PremintResult memory result) {}
}
