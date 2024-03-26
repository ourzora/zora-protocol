// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ContractCreationConfig, PremintConfig, PremintResult, MintArguments} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Minter} from "../interfaces/IERC20Minter.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {IZoraCreator1155PremintExecutor} from "../interfaces/IZoraCreator1155PremintExecutor.sol";
import {IZoraCreator1155DelegatedCreation, IZoraCreator1155DelegatedCreationLegacy, ISupportsAABasedDelegatedTokenCreation} from "../interfaces/IZoraCreator1155DelegatedCreation.sol";
import {EncodedPremintConfig} from "@zoralabs/shared-contracts/premint/PremintEncoding.sol";
import {IMintWithRewardsRecipients} from "../interfaces/IMintWithRewardsRecipients.sol";
import {IERC20Minter} from "../interfaces/IERC20Minter.sol";

interface ILegacyZoraCreator1155DelegatedMinter {
    function delegateSetupNewToken(PremintConfig calldata premintConfig, bytes calldata signature, address sender) external returns (uint256 newTokenId);
}

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

    function legacySetupNewToken(address contractAddress, bytes memory encodedPremintConfig, bytes calldata signature) private returns (uint256) {
        // for use when the erc1155 contract does not support the new delegateSetupNewToken interface, where it expects
        // a PremintConfig as an argument.

        // decode the PremintConfig from the encoded bytes.
        PremintConfig memory premintConfig = abi.decode(encodedPremintConfig, (PremintConfig));

        // call the legacy version of the delegateSetupNewToken function.
        return ILegacyZoraCreator1155DelegatedMinter(contractAddress).delegateSetupNewToken(premintConfig, signature, msg.sender);
    }

    function getOrCreateContractAndToken(
        IZoraCreator1155Factory zora1155Factory,
        ContractCreationConfig calldata contractConfig,
        EncodedPremintConfig memory encodedPremintConfig,
        bytes calldata signature,
        address firstMinter,
        address signerContract
    ) internal returns (PremintResult memory premintResult) {
        // get or create the contract with the given params
        // contract address is deterministic.
        (IZoraCreator1155 tokenContract, bool isNewContract) = getOrCreateContract(zora1155Factory, contractConfig);

        premintResult.contractAddress = address(tokenContract);
        premintResult.createdNewContract = isNewContract;

        if (tokenContract.supportsInterface(type(ISupportsAABasedDelegatedTokenCreation).interfaceId)) {
            // if the contract supports the new interface, we can use it to create the token.

            // pass the signature and the premint config to the token contract to create the token.
            // The token contract will verify the signature and that the signer has permission to create a new token.
            // and then create and setup the token using the given token config.
            premintResult.tokenId = ISupportsAABasedDelegatedTokenCreation(tokenContract).delegateSetupNewToken(
                encodedPremintConfig.premintConfig,
                encodedPremintConfig.premintConfigVersion,
                signature,
                firstMinter,
                signerContract
            );
        } else if (tokenContract.supportsInterface(type(IZoraCreator1155DelegatedCreationLegacy).interfaceId)) {
            if (signerContract != address(0)) {
                revert("Smart contract signing not supported on version of 1155 contract");
            }

            premintResult.tokenId = IZoraCreator1155DelegatedCreationLegacy(address(tokenContract)).delegateSetupNewToken(
                encodedPremintConfig.premintConfig,
                encodedPremintConfig.premintConfigVersion,
                signature,
                firstMinter
            );
        } else {
            // otherwise, we need to use the legacy interface.
            premintResult.tokenId = legacySetupNewToken(address(tokenContract), encodedPremintConfig.premintConfig, signature);
        }
    }

    function performERC20Mint(
        address erc20Minter,
        address currency,
        uint256 pricePerToken,
        uint256 quantityToMint,
        PremintResult memory premintResult,
        MintArguments memory mintArguments
    ) internal {
        if (quantityToMint != 0) {
            address mintReferral = mintArguments.mintRewardsRecipients.length > 0 ? mintArguments.mintRewardsRecipients[0] : address(0);

            uint256 totalValue = pricePerToken * quantityToMint;

            uint256 beforeBalance = IERC20(currency).balanceOf(address(this));
            IERC20(currency).transferFrom(msg.sender, address(this), totalValue);
            uint256 afterBalance = IERC20(currency).balanceOf(address(this));

            if ((beforeBalance + totalValue) != afterBalance) {
                revert IERC20Minter.ERC20TransferSlippage();
            }

            IERC20(currency).approve(erc20Minter, totalValue);

            IERC20Minter(erc20Minter).mint(
                mintArguments.mintRecipient,
                quantityToMint,
                premintResult.contractAddress,
                premintResult.tokenId,
                totalValue,
                currency,
                mintReferral,
                mintArguments.mintComment
            );
        }
    }

    function mintWithEth(
        IZoraCreator1155 tokenContract,
        address fixedPriceMinter,
        uint256 tokenId,
        uint256 quantityToMint,
        MintArguments memory mintArguments
    ) internal {
        bytes memory mintSettings = _toMintSettings(mintArguments);
        if (quantityToMint != 0) {
            if (tokenContract.supportsInterface(type(IMintWithRewardsRecipients).interfaceId)) {
                tokenContract.mint{value: msg.value}(IMinter1155(fixedPriceMinter), tokenId, quantityToMint, mintArguments.mintRewardsRecipients, mintSettings);
            } else {
                // mint the number of specified tokens to the executor
                address mintReferral = mintArguments.mintRewardsRecipients.length > 0 ? mintArguments.mintRewardsRecipients[0] : address(0);

                tokenContract.mintWithRewards{value: msg.value}(IMinter1155(fixedPriceMinter), tokenId, quantityToMint, mintSettings, mintReferral);
            }
        }
    }

    function _toMintSettings(MintArguments memory mintArguments) internal pure returns (bytes memory) {
        return abi.encode(mintArguments.mintRecipient, mintArguments.mintComment);
    }
}
