// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Enjoy} from "_imagine/mint/Enjoy.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {SparksManagerStorageBase} from "./SparksManagerStorageBase.sol";
import {IZoraSparks1155, IUpdateableTokenURI} from "./interfaces/IZoraSparks1155.sol";
import {IZoraSparksAdmin} from "./interfaces/IZoraSparksAdmin.sol";
import {IZoraSparksMinterManager} from "./interfaces/IZoraSparksMinterManager.sol";
import {IZoraSparksManager} from "./interfaces/IZoraSparksManager.sol";
import {TokenConfig} from "./ZoraSparksTypes.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ZoraSparks1155} from "./ZoraSparks1155.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAuthority} from "@openzeppelin/contracts/access/manager/IAuthority.sol";
import {IMinter1155} from "@zoralabs/shared-contracts/interfaces/IMinter1155.sol";
import {ContractCreationConfig, PremintConfigV2, ContractWithAdditionalAdminsCreationConfig, PremintConfigEncoded, MintArguments, PremintResult} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {PremintEncoding} from "@zoralabs/shared-contracts/premint/PremintEncoding.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IZoraSparksManagerErrors} from "./interfaces/IZoraSparksManagerErrors.sol";
import {IVersionedContract} from "@zoralabs/shared-contracts/interfaces/IVersionedContract.sol";
import {ContractVersionBase} from "./version/ContractVersionBase.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IHasContractName} from "@zoralabs/shared-contracts/interfaces/IContractMetadata.sol";
import {BatchDataHelper} from "./utils/BatchDataHelper.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ZoraSparksManagerImpl is
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    SparksManagerStorageBase,
    ContractVersionBase,
    ReentrancyGuardUpgradeable,
    IAuthority,
    IZoraSparksManager,
    IZoraSparksManagerErrors,
    IHasContractName
{
    using SafeERC20 for IERC20;

    constructor() initializer() {}

    function initialize(
        address defaultOwner,
        bytes32 zoraSparksSalt,
        bytes memory zoraSparksCreationCode,
        uint256 initialEthTokenId,
        uint256 initialEthTokenPrice,
        string memory newBaseURI,
        string memory newContractURI
    ) public initializer returns (IZoraSparks1155 sparks) {
        __Ownable_init(defaultOwner);
        __ReentrancyGuard_init();

        if (defaultOwner == address(0)) {
            revert DefaultOwnerCannotBeZero();
        }

        sparks = IZoraSparks1155(Create2.deploy(0, zoraSparksSalt, zoraSparksCreationCode));

        if (ZoraSparks1155(address(sparks)).authority() != address(this)) {
            revert InvalidOwnerForAssociatedZoraSparks();
        }

        _getSparksManagerStorage().sparks = sparks;

        _setMetadataURIs(newContractURI, newBaseURI);

        TokenConfig memory tokenConfig = TokenConfig({price: initialEthTokenPrice, tokenAddress: address(0), redeemHandler: address(0)});
        _createToken(initialEthTokenId, tokenConfig);
    }

    function uri(uint256 tokenId) external view override returns (string memory) {
        return _uri(tokenId);
    }

    function _uri(uint256 tokenId) internal view returns (string memory) {
        SparksManagerStorage storage sparksManagerStorage = _getSparksManagerStorage();
        return string.concat(sparksManagerStorage.baseURI, Strings.toString(tokenId));
    }

    function contractURI() external view override returns (string memory) {
        SparksManagerStorage storage sparksManagerStorage = _getSparksManagerStorage();
        return sparksManagerStorage.contractURI;
    }

    function contractName() external pure override returns (string memory) {
        return "Zora Sparks Manager";
    }

    function setMetadataURIs(string calldata newContractURI, string calldata newBaseURI, uint256[] calldata tokenIdsToNotifyUpdate) external onlyOwner {
        _setMetadataURIs(newContractURI, newBaseURI);

        // iterate through tokenIdsToNotifyUpdate and notify the sparks contract of the updated URIs
        for (uint256 i = 0; i < tokenIdsToNotifyUpdate.length; i++) {
            IUpdateableTokenURI(address(_getSparksManagerStorage().sparks)).notifyUpdatedTokenURI(_uri(tokenIdsToNotifyUpdate[i]), tokenIdsToNotifyUpdate[i]);
        }
    }

    function _setMetadataURIs(string memory newContractURI, string memory newBaseURI) internal {
        // Update URIs
        SparksManagerStorage storage sparksManagerStorage = _getSparksManagerStorage();
        sparksManagerStorage.contractURI = newContractURI;
        sparksManagerStorage.baseURI = newBaseURI;

        // Emit event marking for ZORA indexers
        emit URIsUpdated({contractURI: newContractURI, baseURI: newBaseURI});

        // Emit corresponding events on NFT contract
        IUpdateableTokenURI(address(sparksManagerStorage.sparks)).notifyURIsUpdated({contractURI: newContractURI, baseURI: newBaseURI});
    }

    function mintWithEth(uint256 tokenId, uint256 quantity, address recipient) external payable {
        _getSparksManagerStorage().sparks.mintTokenWithEth{value: msg.value}(tokenId, quantity, recipient, "");
    }

    function mintWithERC20(uint256 tokenId, address tokenAddress, uint quantity, address recipient) external {
        _mintTokenWithERC20(tokenId, tokenAddress, quantity, recipient, "");
    }

    function _mintTokenWithERC20(uint256 tokenId, address tokenAddress, uint quantity, address recipient, bytes memory data) private {
        IZoraSparks1155 sparks = _getSparksManagerStorage().sparks;

        uint256 erc20Quantity = sparks.tokenPrice(tokenId) * quantity;

        // tokens need to be transferred here, then approved to be transferred to the sparks contract,
        // which will transfer the tokens to itself
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), erc20Quantity);
        IERC20(tokenAddress).approve(address(sparks), erc20Quantity);

        sparks.mintTokenWithERC20(tokenId, tokenAddress, quantity, recipient, data);
    }

    function zoraSparks1155() public view override returns (IZoraSparks1155) {
        return _getSparksManagerStorage().sparks;
    }

    function createToken(uint256 tokenId, TokenConfig calldata tokenConfig) public override onlyOwner {
        _createToken(tokenId, tokenConfig);
    }

    function _createToken(uint256 tokenId, TokenConfig memory tokenConfig) private {
        IZoraSparks1155 sparks = _getSparksManagerStorage().sparks;
        sparks.createToken(tokenId, tokenConfig);
        IUpdateableTokenURI(address(sparks)).notifyUpdatedTokenURI(_uri(tokenId), tokenId);
    }

    function canCall(address caller, address /* target */, bytes4 /* selector */) external view returns (bool) {
        return caller == address(this);
    }

    function implementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /// @notice Ensures the caller is authorized to upgrade the contract
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal override onlyOwner {
        if (!Strings.equal(IHasContractName(_newImpl).contractName(), this.contractName())) {
            revert UpgradeToMismatchedContractName(this.contractName(), IHasContractName(_newImpl).contractName());
        }
    }
}
