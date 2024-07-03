// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {PremintConfig, ContractCreationConfig, ContractWithAdditionalAdminsCreationConfig, PremintResult, MintArguments, TokenCreationConfigV3, PremintConfigV3} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Minter} from "../interfaces/IERC20Minter.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {IZoraCreator1155PremintExecutor} from "../interfaces/IZoraCreator1155PremintExecutor.sol";
import {IZoraCreator1155DelegatedCreation, IZoraCreator1155DelegatedCreationLegacy, ISupportsAABasedDelegatedTokenCreation} from "../interfaces/IZoraCreator1155DelegatedCreation.sol";
import {IMintWithRewardsRecipients} from "../interfaces/IMintWithRewardsRecipients.sol";
import {IMintWithRewardsLegacy} from "../interfaces/IMintWithRewardsLegacy.sol";

interface ILegacyZoraCreator1155DelegatedMinter {
    function delegateSetupNewToken(PremintConfig calldata premintConfig, bytes calldata signature, address sender) external returns (uint256 newTokenId);
}

struct GetOrCreateContractResult {
    IZoraCreator1155 tokenContract;
    bool isNewContract;
}

library ZoraCreator1155PremintExecutorImplLib {
    function getOrCreateContract(
        IZoraCreator1155Factory zora1155Factory,
        ContractWithAdditionalAdminsCreationConfig memory contractConfig
    ) internal returns (address tokenContract, bool isNewContract) {
        // get contract address based on contract creation parameters
        address contractAddress = getContractWithAdditionalAdminsAddress(zora1155Factory, contractConfig);
        // first we see if the code is already deployed for the contract
        isNewContract = contractAddress.code.length == 0;

        if (isNewContract) {
            // if address doesn't exist for hash, create it
            tokenContract = address(createContract(zora1155Factory, contractConfig));
        } else {
            tokenContract = contractAddress;
        }
    }

    uint256 private constant CONTRACT_BASE_ID = 0;
    uint256 private constant PERMISSION_BIT_ADMIN = 2 ** 1;
    uint256 private constant PERMISSION_BIT_MINTER = 2 ** 2;

    function createContract(
        IZoraCreator1155Factory zora1155Factory,
        ContractWithAdditionalAdminsCreationConfig memory contractConfig
    ) internal returns (IZoraCreator1155 tokenContract) {
        // we need to build the setup actions, that must:
        bytes[] memory setupActions = toSetupActions(contractConfig.additionalAdmins);

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

    function toSetupActions(address[] memory additionalAdmins) internal pure returns (bytes[] memory setupActions) {
        setupActions = new bytes[](additionalAdmins.length);

        for (uint256 i = 0; i < additionalAdmins.length; i++) {
            setupActions[i] = abi.encodeWithSelector(IZoraCreator1155.addPermission.selector, CONTRACT_BASE_ID, additionalAdmins[i], PERMISSION_BIT_ADMIN);
        }
    }

    /// Gets the deterministic contract address for the given contract creation config.
    /// Contract address is generated deterministically from a hash based on the contract uri, contract name,
    /// contract admin, and the msg.sender, which is this contract's address.
    function getContractAddress(IZoraCreator1155Factory zora1155Factory, ContractCreationConfig calldata contractConfig) internal view returns (address) {
        return
            zora1155Factory.deterministicContractAddress(address(this), contractConfig.contractURI, contractConfig.contractName, contractConfig.contractAdmin);
    }

    function getContractWithAdditionalAdminsAddress(
        IZoraCreator1155Factory zora1155Factory,
        ContractWithAdditionalAdminsCreationConfig memory contractConfig
    ) internal view returns (address) {
        return
            zora1155Factory.deterministicContractAddressWithSetupActions(
                address(this),
                contractConfig.contractURI,
                contractConfig.contractName,
                contractConfig.contractAdmin,
                toSetupActions(contractConfig.additionalAdmins)
            );
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

    function getOrCreateToken(
        IZoraCreator1155 tokenContract,
        bytes memory premintConfig,
        bytes32 premintConfigVersion,
        bytes calldata signature,
        address firstMinter,
        address signerContract
    ) internal returns (uint256 tokenId) {
        if (tokenContract.supportsInterface(type(ISupportsAABasedDelegatedTokenCreation).interfaceId)) {
            // if the contract supports the new interface, we can use it to create the token.

            // pass the signature and the premint config to the token contract to create the token.
            // The token contract will verify the signature and that the signer has permission to create a new token.
            // and then create and setup the token using the given token config.
            tokenId = ISupportsAABasedDelegatedTokenCreation(tokenContract).delegateSetupNewToken(
                premintConfig,
                premintConfigVersion,
                signature,
                firstMinter,
                signerContract
            );
        } else if (tokenContract.supportsInterface(type(IZoraCreator1155DelegatedCreationLegacy).interfaceId)) {
            if (signerContract != address(0)) {
                revert("Smart contract signing not supported on version of 1155 contract");
            }

            tokenId = IZoraCreator1155DelegatedCreationLegacy(address(tokenContract)).delegateSetupNewToken(
                premintConfig,
                premintConfigVersion,
                signature,
                firstMinter
            );
        } else {
            // otherwise, we need to use the legacy interface.
            tokenId = legacySetupNewToken(address(tokenContract), premintConfig, signature);
        }
    }

    function performERC20Mint(address minter, uint256 quantityToMint, address contractAddress, uint256 tokenId, MintArguments memory mintArguments) internal {
        IERC20Minter.SalesConfig memory salesConfig = IERC20Minter(minter).sale(contractAddress, tokenId);

        _performERC20Mint(minter, salesConfig.currency, salesConfig.pricePerToken, quantityToMint, contractAddress, tokenId, mintArguments);
    }

    function _performERC20Mint(
        address erc20Minter,
        address currency,
        uint256 pricePerToken,
        uint256 quantityToMint,
        address contractAddress,
        uint256 tokenId,
        MintArguments memory mintArguments
    ) private {
        address mintReferral = mintArguments.mintRewardsRecipients.length > 0 ? mintArguments.mintRewardsRecipients[0] : address(0);

        uint256 totalValue = pricePerToken * quantityToMint;

        {
            uint256 beforeBalance = IERC20(currency).balanceOf(address(this));
            IERC20(currency).transferFrom(msg.sender, address(this), totalValue);
            uint256 afterBalance = IERC20(currency).balanceOf(address(this));

            if ((beforeBalance + totalValue) != afterBalance) {
                revert IERC20Minter.ERC20TransferSlippage();
            }
        }

        IERC20(currency).approve(erc20Minter, totalValue);

        IERC20Minter(erc20Minter).mint{value: msg.value}(
            mintArguments.mintRecipient,
            quantityToMint,
            contractAddress,
            tokenId,
            totalValue,
            currency,
            mintReferral,
            mintArguments.mintComment
        );
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

                IMintWithRewardsLegacy(address(tokenContract)).mintWithRewards{value: msg.value}(
                    IMinter1155(fixedPriceMinter),
                    tokenId,
                    quantityToMint,
                    mintSettings,
                    mintReferral
                );
            }
        }
    }

    function _toMintSettings(MintArguments memory mintArguments) internal pure returns (bytes memory) {
        return abi.encode(mintArguments.mintRecipient, mintArguments.mintComment);
    }

    function isAuthorizedToCreatePremint(
        address signer,
        address premintContractConfigContractAdmin,
        address contractAddress,
        address[] memory additionalAdmins
    ) internal view returns (bool authorized) {
        // if contract hasn't been created, signer must be the contract admin on the premint config
        if (contractAddress.code.length == 0) {
            if (signer == premintContractConfigContractAdmin) {
                return true;
            } else {
                return signerIsMinterInAdditionalAdmins(signer, additionalAdmins);
            }
        } else {
            // if contract has been created, signer must have mint new token permission
            authorized = IZoraCreator1155(contractAddress).isAdminOrRole(signer, CONTRACT_BASE_ID, PERMISSION_BIT_MINTER);
        }
    }

    function signerIsMinterInAdditionalAdmins(address signer, address[] memory additionalAdmins) private pure returns (bool) {
        for (uint256 i = 0; i < additionalAdmins.length; i++) {
            if (additionalAdmins[i] == signer) {
                return true;
            }
        }

        return false;
    }
}
