// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Enjoy} from "_imagine/mint/Enjoy.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {IZoraCreator1155PremintExecutorV2} from "@zoralabs/shared-contracts/interfaces/IZoraCreator1155PremintExecutorV2.sol";
import {MintsManagerStorageBase} from "./MintsManagerStorageBase.sol";
import {IZoraMints1155, IUpdateableTokenURI} from "./interfaces/IZoraMints1155.sol";
import {IZoraMintsAdmin} from "./interfaces/IZoraMintsAdmin.sol";
import {IZoraMintsMinterManager} from "./interfaces/IZoraMintsMinterManager.sol";
import {IZoraMintsManager} from "./interfaces/IZoraMintsManager.sol";
import {TokenConfig} from "./ZoraMintsTypes.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ZoraMints1155} from "./ZoraMints1155.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAuthority} from "@openzeppelin/contracts/access/manager/IAuthority.sol";
import {IMintWithMints} from "./IMintWithMints.sol";
import {IMinter1155} from "@zoralabs/shared-contracts/interfaces/IMinter1155.sol";
import {ContractCreationConfig, PremintConfigV2, MintArguments, PremintResult} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ICollectWithZoraMints} from "./ICollectWithZoraMints.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IZoraMintsManagerErrors} from "./interfaces/IZoraMintsManagerErrors.sol";
import {IVersionedContract} from "@zoralabs/shared-contracts/interfaces/IVersionedContract.sol";
import {ContractVersionBase} from "./version/ContractVersionBase.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IHasContractName} from "@zoralabs/shared-contracts/interfaces/IContractMetadata.sol";
import {BatchDataHelper} from "./utils/BatchDataHelper.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract ZoraMintsManagerImpl is
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    MintsManagerStorageBase,
    ContractVersionBase,
    ReentrancyGuardUpgradeable,
    IAuthority,
    IZoraMintsManager,
    ICollectWithZoraMints,
    IZoraMintsManagerErrors,
    IHasContractName
{
    using SafeERC20 for IERC20;
    IZoraCreator1155PremintExecutorV2 immutable premintExecutor;

    constructor(IZoraCreator1155PremintExecutorV2 _premintExecutor) {
        if (address(_premintExecutor) == address(0)) {
            revert PremintExecutorCannotBeZero();
        }

        premintExecutor = _premintExecutor;
        _disableInitializers();
    }

    function initialize(
        address defaultOwner,
        bytes32 zoraMintsSalt,
        bytes memory zoraMintsCreationCode,
        uint256 initialEthTokenId,
        uint256 initialEthTokenPrice,
        string memory newBaseURI,
        string memory newContractURI
    ) public initializer returns (IZoraMints1155 mints) {
        __Ownable_init(defaultOwner);
        __ReentrancyGuard_init();

        if (defaultOwner == address(0)) {
            revert DefaultOwnerCannotBeZero();
        }

        mints = IZoraMints1155(Create2.deploy(0, zoraMintsSalt, zoraMintsCreationCode));

        if (ZoraMints1155(address(mints)).authority() != address(this)) {
            revert InvalidOwnerForAssociatedZoraMints();
        }

        _getMintsManagerStorage().mints = mints;

        _setMetadataURIs(newContractURI, newBaseURI);

        TokenConfig memory tokenConfig = TokenConfig({price: initialEthTokenPrice, tokenAddress: address(0), redeemHandler: address(0)});
        _createToken(initialEthTokenId, tokenConfig, true);
    }

    function uri(uint256 tokenId) external view override returns (string memory) {
        return _uri(tokenId);
    }

    function _uri(uint256 tokenId) internal view returns (string memory) {
        MintsManagerStorage storage mintsManagerStorage = _getMintsManagerStorage();
        return string.concat(mintsManagerStorage.baseURI, Strings.toString(tokenId));
    }

    function contractURI() external view override returns (string memory) {
        MintsManagerStorage storage mintsManagerStorage = _getMintsManagerStorage();
        return mintsManagerStorage.contractURI;
    }

    function contractName() external pure override returns (string memory) {
        return "Zora Mints Manager";
    }

    function setMetadataURIs(string calldata newContractURI, string calldata newBaseURI, uint256[] calldata tokenIdsToNotifyUpdate) external onlyOwner {
        _setMetadataURIs(newContractURI, newBaseURI);

        // iterate through tokenIdsToNotifyUpdate and notify the mints contract of the updated URIs
        for (uint256 i = 0; i < tokenIdsToNotifyUpdate.length; i++) {
            IUpdateableTokenURI(address(_getMintsManagerStorage().mints)).notifyUpdatedTokenURI(_uri(tokenIdsToNotifyUpdate[i]), tokenIdsToNotifyUpdate[i]);
        }
    }

    function _setMetadataURIs(string memory newContractURI, string memory newBaseURI) internal {
        // Update URIs
        MintsManagerStorage storage mintsManagerStorage = _getMintsManagerStorage();
        mintsManagerStorage.contractURI = newContractURI;
        mintsManagerStorage.baseURI = newBaseURI;

        // Emit event marking for ZORA indexers
        emit URIsUpdated({contractURI: newContractURI, baseURI: newBaseURI});

        // Emit corresponding events on NFT contract
        IUpdateableTokenURI(address(mintsManagerStorage.mints)).notifyURIsUpdated({contractURI: newContractURI, baseURI: newBaseURI});
    }

    /// @notice Retrieves the price in ETH of the currently mintable ETH-based token.
    function getEthPrice() external view override returns (uint256) {
        MintsManagerStorage storage mintsStorage = _getMintsManagerStorage();
        return mintsStorage.mints.tokenPrice(mintsStorage.mintableEthToken);
    }

    /// @notice Gets the token id of the current mintable ETH-based token.
    function mintableEthToken() external view override returns (uint256) {
        return _getMintsManagerStorage().mintableEthToken;
    }

    /// This will be moved to the Mints Manager
    function mintWithEth(uint256 quantity, address recipient) external payable override returns (uint256 mintableTokenId) {
        MintsManagerStorage storage mintsManagerStorage = _getMintsManagerStorage();
        mintableTokenId = mintsManagerStorage.mintableEthToken;
        mintsManagerStorage.mints.mintTokenWithEth{value: msg.value}(mintableTokenId, quantity, recipient, "");
    }

    /// This will be moved to the Mints Manager
    function mintWithERC20(address tokenAddress, uint quantity, address recipient) external returns (uint256 mintableTokenId) {
        MintsManagerStorage storage mintsManagerStorage = _getMintsManagerStorage();
        mintableTokenId = mintsManagerStorage.mintableERC20Token[tokenAddress];

        _mintTokenWithERC20(mintableTokenId, tokenAddress, quantity, recipient, "");
    }

    function _mintTokenWithERC20(uint256 tokenId, address tokenAddress, uint quantity, address recipient, bytes memory data) private {
        IZoraMints1155 mints = _getMintsManagerStorage().mints;

        uint256 erc20Quantity = mints.tokenPrice(tokenId) * quantity;

        // tokens need to be transferred here, then approved to be transferred to the mints contract,
        // which will transfer the tokens to itself
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), erc20Quantity);
        IERC20(tokenAddress).approve(address(mints), erc20Quantity);

        mints.mintTokenWithERC20(tokenId, tokenAddress, quantity, recipient, data);
    }

    function zoraMints1155() public view override returns (IZoraMints1155) {
        return _getMintsManagerStorage().mints;
    }

    // note: this is to be moved to the mints manager
    function setDefaultMintable(address tokenAddress, uint256 tokenId) external override onlyOwner {
        _setDefaultMintable(tokenAddress, tokenId);
    }

    function createToken(uint256 tokenId, TokenConfig calldata tokenConfig, bool defaultMintable) public override onlyOwner {
        _createToken(tokenId, tokenConfig, defaultMintable);
    }

    function _createToken(uint256 tokenId, TokenConfig memory tokenConfig, bool defaultMintable) private {
        IZoraMints1155 mints = _getMintsManagerStorage().mints;
        mints.createToken(tokenId, tokenConfig);
        IUpdateableTokenURI(address(mints)).notifyUpdatedTokenURI(_uri(tokenId), tokenId);
        if (defaultMintable) {
            _setDefaultMintable(tokenConfig.tokenAddress, tokenId);
        }
    }

    function _setDefaultMintable(address tokenAddress, uint256 tokenId) private {
        MintsManagerStorage storage mintsManagerStorage = _getMintsManagerStorage();
        TokenConfig memory tokenConfig = mintsManagerStorage.mints.getTokenConfig(tokenId);
        if (tokenConfig.price == 0) {
            revert TokenDoesNotExist();
        }
        if (tokenConfig.tokenAddress != tokenAddress) {
            revert TokenMismatch(tokenConfig.tokenAddress, tokenAddress);
        }

        if (tokenAddress == address(0)) {
            mintsManagerStorage.mintableEthToken = tokenId;
        } else {
            mintsManagerStorage.mintableERC20Token[tokenAddress] = tokenId;
        }

        emit DefaultMintableTokenSet(tokenAddress, tokenId);
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

    // meant to be called by the 1155 mints contract
    function collect(
        IMintWithMints zoraCreator1155Contract,
        IMinter1155 minter,
        uint256 zoraCreator1155TokenId,
        CollectMintArguments calldata collectMintArguments
    ) external payable override onlyThis {
        _collect(
            zoraCreator1155Contract,
            minter,
            zoraCreator1155TokenId,
            collectMintArguments.mintRewardsRecipients,
            collectMintArguments.minterArguments,
            collectMintArguments.mintComment
        );
    }

    function decodeMintRecipientAndComment(bytes memory minterArguments) external pure returns (address mintTo, string memory mintComment) {
        (mintTo, mintComment) = abi.decode(minterArguments, (address, string));
    }

    function collectPremintV2(
        ContractCreationConfig calldata contractConfig,
        PremintConfigV2 calldata premintConfig,
        bytes calldata signature,
        MintArguments calldata mintArguments,
        address signerContract
    ) external payable override onlyThis returns (PremintResult memory result) {
        MintArguments memory emptyArguments;
        TransferredMints memory transferredMints = _getTransferredMints();
        address firstMinter = transferredMints.from;
        // call premint with mints on the premint executor, which will get or create the contract,
        // get or create a token for the uid.
        // quantity to mint is 0, meaning that this step will just get or create the contract and token
        result = premintExecutor.premintV2WithSignerContract{value: msg.value}(
            contractConfig,
            premintConfig,
            signature,
            0,
            // these arent used in the premint when quantity to mint is 0, so we can pass empty arguments
            emptyArguments,
            firstMinter,
            signerContract
        );

        // collect tokens from the creator contract using MINTs
        _collect(
            IMintWithMints(result.contractAddress),
            IMinter1155(premintConfig.tokenConfig.fixedPriceMinter),
            result.tokenId,
            mintArguments.mintRewardsRecipients,
            abi.encode(mintArguments.mintRecipient, ""),
            mintArguments.mintComment
        );
    }

    function _collect(
        IMintWithMints zoraCreator1155Contract,
        IMinter1155 minter,
        uint256 zoraCreator1155TokenId,
        address[] calldata rewardsRecipients,
        bytes memory minterArguments,
        string memory mintComment
    ) internal {
        uint256[] memory tokenIds;
        uint256[] memory quantities;
        address from;
        {
            TransferredMints memory transferredMints = _getTransferredMints();
            tokenIds = transferredMints.tokenIds;
            quantities = transferredMints.quantities;
            from = transferredMints.from;
        }

        if (tokenIds.length == 0) {
            revert NoTokensTransferred();
        }
        // ensure that the contract supports the interface IMinWithMints
        if (!IERC165(address(zoraCreator1155Contract)).supportsInterface(type(IMintWithMints).interfaceId)) {
            revert MintWithMintsNotSupportedOnContract();
        }

        IZoraMints1155 mints1155 = _getMintsManagerStorage().mints;
        mints1155.setApprovalForAll(address(zoraCreator1155Contract), true);
        // call the Zora Creator 1155 contract to mint the creator tokens.  The creator contract will redeem the MINTs.
        uint256 quantityMinted = zoraCreator1155Contract.mintWithMints{value: msg.value}(
            tokenIds,
            quantities,
            minter,
            zoraCreator1155TokenId,
            rewardsRecipients,
            // here we strip out the comment since it doesn't work properly with msg.sender changing.
            minterArguments
        );
        mints1155.setApprovalForAll(address(zoraCreator1155Contract), false);

        if (bytes(mintComment).length > 0) {
            // the message sender that initiated the call from the mints contract is considered the commenter.
            emit MintComment(from, address(zoraCreator1155Contract), zoraCreator1155TokenId, quantityMinted, mintComment);
        }

        emit Collected(tokenIds, quantities, address(zoraCreator1155Contract), zoraCreator1155TokenId);
    }

    bytes4 constant ON_ERC1155_BATCH_RECEIVED_HASH = IERC1155Receiver.onERC1155BatchReceived.selector;
    bytes4 constant ON_ERC1155_RECEIVED_HASH = IERC1155Receiver.onERC1155Received.selector;

    /// @dev Only the pool manager may call this function
    modifier onlyMints() {
        if (msg.sender != address(zoraMints1155())) {
            revert NotZoraMints1155();
        }

        _;
    }

    /// @dev Only the pool manager may call this function
    modifier onlyThis() {
        if (msg.sender != address(this)) {
            revert NotSelfCall();
        }

        _;
    }

    function _getTransferredMints() private view returns (TransferredMints memory transferredMints) {
        transferredMints = _getMintsManagerStorage().transferredMints;
        if (transferredMints.from == address(0)) {
            revert NoTokensTransferred();
        }
    }

    function onERC1155Received(address, address from, uint256 id, uint256 value, bytes calldata data) external onlyMints returns (bytes4) {
        (uint256[] memory ids, uint256[] memory quantities) = BatchDataHelper.asSingletonArrays(id, value);
        _setTransferredMints(from, ids, quantities);

        if (data.length != 0) {
            _handleReceivedCallAndRevertIfFails(data);
        }

        _clearTransferredMints();

        return ON_ERC1155_RECEIVED_HASH;
    }

    function onERC1155BatchReceived(
        address,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external onlyMints returns (bytes4) {
        _setTransferredMints(from, ids, values);

        if (data.length != 0) {
            _handleReceivedCallAndRevertIfFails(data);
        }

        _clearTransferredMints();

        return ON_ERC1155_BATCH_RECEIVED_HASH;
    }

    function callWithTransferTokens(
        address callFrom,
        uint256[] calldata tokenIds,
        uint256[] calldata quantities,
        bytes calldata call
    ) external payable onlyMints returns (bool success, bytes memory result) {
        _setTransferredMints(callFrom, tokenIds, quantities);
        (success, result) = _handleReceivedCall(call, msg.value);
        _clearTransferredMints();
    }

    function _handleReceivedCallAndRevertIfFails(bytes calldata data) private {
        (bool success, bytes memory result) = _handleReceivedCall(data, 0);

        if (!success) {
            _revertWithUnwrappedError(result);
        }
    }

    function _handleReceivedCall(bytes calldata data, uint256 value) private returns (bool success, bytes memory result) {
        bytes4 selector = bytes4(data[:4]);

        if (selector != ICollectWithZoraMints.collect.selector && selector != ICollectWithZoraMints.collectPremintV2.selector) {
            revert UnknownUserAction(selector);
        }

        return address(this).call{value: value}(data);
    }

    function _revertWithUnwrappedError(bytes memory result) private pure {
        // source: https://yos.io/2022/07/16/bubbling-up-errors-in-solidity/#:~:text=An%20inline%20assembly%20block%20is,object%20is%20returned%20in%20result%20.
        // if no error message, revert with generic error
        if (result.length == 0) {
            revert ERC1155BatchReceivedCallFailed();
        }
        assembly {
            // We use Yul's revert() to unwrap errors from this contract.
            revert(add(32, result), mload(result))
        }
    }

    function _setTransferredMints(address from, uint256[] memory tokenIds, uint256[] memory quantities) private {
        _getMintsManagerStorage().transferredMints = TransferredMints({from: from, tokenIds: tokenIds, quantities: quantities});
    }

    function _clearTransferredMints() private {
        TransferredMints storage transferredMints = _getMintsManagerStorage().transferredMints;
        transferredMints.from = address(0);
        transferredMints.tokenIds = new uint256[](0);
        transferredMints.quantities = new uint256[](0);
    }
}
