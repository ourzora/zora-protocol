// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ContractCreationConfig} from "./ZoraCreator1155Attribution.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {IZoraCreator1155PremintExecutor} from "../interfaces/IZoraCreator1155PremintExecutor.sol";

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

    function premint(
        IZoraCreator1155Factory zora1155Factory,
        ContractCreationConfig calldata contractConfig,
        bytes memory encodedPremintConfig,
        bytes32 premintVersion,
        bytes calldata signature,
        uint256 quantityToMint,
        address fixedPriceMinter,
        IZoraCreator1155PremintExecutor.MintArguments memory mintArguments
    ) internal returns (IZoraCreator1155PremintExecutor.PremintResult memory) {
        // get or create the contract with the given params
        // contract address is deterministic.
        (IZoraCreator1155 tokenContract, bool isNewContract) = getOrCreateContract(zora1155Factory, contractConfig);

        // pass the signature and the premint config to the token contract to create the token.
        // The token contract will verify the signature and that the signer has permission to create a new token.
        // and then create and setup the token using the given token config.
        uint256 newTokenId = tokenContract.delegateSetupNewToken(encodedPremintConfig, premintVersion, signature, msg.sender);

        _performMint(tokenContract, fixedPriceMinter, newTokenId, quantityToMint, mintArguments);

        return IZoraCreator1155PremintExecutor.PremintResult({contractAddress: address(tokenContract), tokenId: newTokenId, createdNewContract: isNewContract});
    }

    function _performMint(
        IZoraCreator1155 tokenContract,
        address fixedPriceMinter,
        uint256 tokenId,
        uint256 quantityToMint,
        IZoraCreator1155PremintExecutor.MintArguments memory mintArguments
    ) internal {
        bytes memory mintSettings = abi.encode(mintArguments.mintRecipient, mintArguments.mintComment);
        if (quantityToMint != 0)
            // mint the number of specified tokens to the executor
            tokenContract.mintWithRewards{value: msg.value}(IMinter1155(fixedPriceMinter), tokenId, quantityToMint, mintSettings, mintArguments.mintReferral);
    }
}
