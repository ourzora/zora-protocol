// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ContractCreationConfig} from "./ZoraCreator1155Attribution.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";

library ZoraCreator1155PremintExecutorImplLib {
    function getOrCreateContract(
        IZoraCreator1155Factory zora1155Factory,
        ContractCreationConfig calldata contractConfig
    ) internal returns (IZoraCreator1155 tokenContract, bool isNewContract) {
        address contractAddress = getContractAddress(zora1155Factory, contractConfig);
        // first we see if the code is already deployed for the contract
        isNewContract = contractAddress.code.length == 0;

        if (isNewContract) {
            // if address doesn't exist for hash, create it
            tokenContract = createContract(zora1155Factory, contractConfig);
        } else {
            tokenContract = IZoraCreator1155(contractAddress);
        }
    }

    function createContract(
        IZoraCreator1155Factory zora1155Factory,
        ContractCreationConfig calldata contractConfig
    ) internal returns (IZoraCreator1155 tokenContract) {
        // we need to build the setup actions, that must:
        bytes[] memory setupActions = new bytes[](0);

        // create the contract via the factory.
        address newContractAddresss = zora1155Factory.createContractDeterministic(
            contractConfig.contractURI,
            contractConfig.contractName,
            // default royalty config is empty, since we set it on a token level
            ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyBPS: 0, royaltyRecipient: address(0), royaltyMintSchedule: 0}),
            payable(contractConfig.contractAdmin),
            setupActions
        );
        tokenContract = IZoraCreator1155(newContractAddresss);
    }

    /// Gets the deterministic contract address for the given contract creation config.
    /// Contract address is generated deterministically from a hash based on the contract uri, contract name,
    /// contract admin, and the msg.sender, which is this contract's address.
    function getContractAddress(IZoraCreator1155Factory zora1155Factory, ContractCreationConfig calldata contractConfig) internal view returns (address) {
        return
            zora1155Factory.deterministicContractAddress(address(this), contractConfig.contractURI, contractConfig.contractName, contractConfig.contractAdmin);
    }

    function encodeMintArguments(address mintRecipient, string memory mintComment) internal pure returns (bytes memory) {
        return abi.encode(mintRecipient, mintComment);
    }

    function decodeMintArguments(bytes memory mintArguments) internal pure returns (address mintRecipient, string memory mintComment) {
        return abi.decode(mintArguments, (address, string));
    }
}
