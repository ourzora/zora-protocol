// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Initializable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {IZoraCreator1155Initializer} from "../interfaces/IZoraCreator1155Initializer.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {IContractMetadata} from "../interfaces/IContractMetadata.sol";
import {Ownable2StepUpgradeable} from "../utils/ownable/Ownable2StepUpgradeable.sol";
import {Zora1155} from "../proxies/Zora1155.sol";
import {Create2Upgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/Create2Upgradeable.sol";
import {CREATE3} from "solmate/src/utils/CREATE3.sol";

import {ContractVersionBase} from "../version/ContractVersionBase.sol";

/// @title ZoraCreator1155FactoryImpl
/// @notice Factory contract for creating new ZoraCreator1155 contracts
contract ZoraCreator1155FactoryImpl is IZoraCreator1155Factory, Ownable2StepUpgradeable, ContractVersionBase, UUPSUpgradeable, IContractMetadata {
    IZoraCreator1155 public immutable zora1155Impl;
    IMinter1155 public immutable merkleMinter;
    IMinter1155 public immutable fixedPriceMinter;
    IMinter1155 public immutable redeemMinterFactory;

    constructor(IZoraCreator1155 _zora1155Impl, IMinter1155 _merkleMinter, IMinter1155 _fixedPriceMinter, IMinter1155 _redeemMinterFactory) initializer {
        if (address(_zora1155Impl) == address(0)) {
            revert Constructor_ImplCannotBeZero();
        }
        zora1155Impl = _zora1155Impl;
        merkleMinter = _merkleMinter;
        fixedPriceMinter = _fixedPriceMinter;
        redeemMinterFactory = _redeemMinterFactory;
    }

    /// @notice ContractURI for contract information with the strategy
    function contractURI() external pure returns (string memory) {
        return "https://github.com/ourzora/zora-1155-contracts/";
    }

    /// @notice The name of the sale strategy
    function contractName() external pure returns (string memory) {
        return "ZORA 1155 Contract Factory";
    }

    /// @notice The default minters for new 1155 contracts
    function defaultMinters() external view returns (IMinter1155[] memory minters) {
        minters = new IMinter1155[](3);
        minters[0] = fixedPriceMinter;
        minters[1] = merkleMinter;
        minters[2] = redeemMinterFactory;
    }

    function initialize(address _initialOwner) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();

        emit FactorySetup();
    }

    /// @notice Creates a new ZoraCreator1155 contract
    /// @param newContractURI The URI for the contract metadata
    /// @param name The name of the contract
    /// @param defaultRoyaltyConfiguration The default royalty configuration for the contract
    /// @param defaultAdmin The default admin for the contract
    /// @param setupActions The actions to perform on the new contract upon initialization
    function createContract(
        string calldata newContractURI,
        string calldata name,
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        address payable defaultAdmin,
        bytes[] calldata setupActions
    ) external returns (address) {
        Zora1155 newContract = new Zora1155(address(zora1155Impl));

        _initializeContract(Zora1155(newContract), newContractURI, name, defaultRoyaltyConfiguration, defaultAdmin, setupActions);

        return address(newContract);
    }

    function createContractDeterministic(
        string calldata newContractURI,
        string calldata name,
        ICreatorRoyaltiesControl.RoyaltyConfiguration calldata defaultRoyaltyConfiguration,
        address payable defaultAdmin,
        bytes[] calldata setupActions
    ) external returns (address) {
        bytes32 digest = _hashContract(msg.sender, newContractURI, name, defaultAdmin);

        address createdContract = CREATE3.deploy(digest, abi.encodePacked(type(Zora1155).creationCode, abi.encode(zora1155Impl)), 0);

        Zora1155 newContract = Zora1155(payable(createdContract));

        _initializeContract(newContract, newContractURI, name, defaultRoyaltyConfiguration, defaultAdmin, setupActions);

        return address(newContract);
    }

    function deterministicContractAddress(
        address msgSender,
        string calldata newContractURI,
        string calldata name,
        address contractAdmin
    ) external view returns (address) {
        bytes32 digest = _hashContract(msgSender, newContractURI, name, contractAdmin);

        return CREATE3.getDeployed(digest);
    }

    function _initializeContract(
        Zora1155 newContract,
        string calldata newContractURI,
        string calldata name,
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        address payable defaultAdmin,
        bytes[] calldata setupActions
    ) private {
        emit SetupNewContract({
            newContract: address(newContract),
            creator: msg.sender,
            defaultAdmin: defaultAdmin,
            contractURI: newContractURI,
            name: name,
            defaultRoyaltyConfiguration: defaultRoyaltyConfiguration
        });

        IZoraCreator1155Initializer(address(newContract)).initialize(name, newContractURI, defaultRoyaltyConfiguration, defaultAdmin, setupActions);
    }

    function _hashContract(address msgSender, string calldata newContractURI, string calldata name, address contractAdmin) private pure returns (bytes32) {
        return keccak256(abi.encode(msgSender, contractAdmin, _stringHash(newContractURI), _stringHash(name)));
    }

    function _stringHash(string calldata value) private pure returns (bytes32) {
        return keccak256(bytes(value));
    }

    ///                                                          ///
    ///                         MANAGER UPGRADE                  ///
    ///                                                          ///

    /// @notice Ensures the caller is authorized to upgrade the contract
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal override onlyOwner {
        if (!_equals(IContractMetadata(_newImpl).contractName(), this.contractName())) {
            revert UpgradeToMismatchedContractName(this.contractName(), IContractMetadata(_newImpl).contractName());
        }
    }

    /// @notice Returns the current implementation address
    function implementation() external view returns (address) {
        return _getImplementation();
    }

    function _equals(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(bytes(a)) == keccak256(bytes(b)));
    }
}
