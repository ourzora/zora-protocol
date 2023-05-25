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
import {FactoryManagedUpgradeGate} from "../upgrades/FactoryManagedUpgradeGate.sol";
import {Zora1155} from "../proxies/Zora1155.sol";

import {ContractVersionBase} from "../version/ContractVersionBase.sol";

import {EIP712Upgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSAUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";

import {Create2Upgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/Create2Upgradeable.sol";

error InvalidDelegateSignature();
error InvalidNonce();

/// @title ZoraCreator1155FactoryImpl
/// @notice Factory contract for creating new ZoraCreator1155 contracts
contract ZoraCreator1155FactoryImpl is
    IZoraCreator1155Factory,
    ContractVersionBase,
    FactoryManagedUpgradeGate,
    UUPSUpgradeable,
    EIP712Upgradeable,
    IContractMetadata
{
    IZoraCreator1155 public immutable implementation;

    IMinter1155 public immutable merkleMinter;
    IMinter1155 public immutable fixedPriceMinter;
    IMinter1155 public immutable redeemMinterFactory;

    constructor(IZoraCreator1155 _implementation, IMinter1155 _merkleMinter, IMinter1155 _fixedPriceMinter, IMinter1155 _redeemMinterFactory) initializer {
        implementation = _implementation;
        if (address(implementation) == address(0)) {
            revert Constructor_ImplCannotBeZero();
        }
        merkleMinter = _merkleMinter;
        fixedPriceMinter = _fixedPriceMinter;
        redeemMinterFactory = _redeemMinterFactory;
    }

    /// @notice ContractURI for contract information with the strategy
    function contractURI() external pure returns (string memory) {
        return "https://github.com/ourzora/zora-1155-contracts/";
    }

    /// @notice The name of the sale strategy
    function contractName() public pure returns (string memory) {
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
        __EIP712_init(contractName(), contractVersion());
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
        ICreatorRoyaltiesControl.RoyaltyConfiguration calldata defaultRoyaltyConfiguration,
        address payable defaultAdmin,
        bytes[] calldata setupActions
    ) external returns (address) {
        // call private _createContract with msg.sender as the creator
        return _createContract(msg.sender, newContractURI, name, defaultRoyaltyConfiguration, defaultAdmin, setupActions);
    }

    bytes32 constant DELEGATE_CREATE_TYPEHASH =
        keccak256(
            "delegateCreate(address creator,string newContractURI,string name, ICreatorRoyaltiesControl.RoyaltyConfiguration defaultRoyaltyConfiguration,bytes[] setupActions,address erc1155implementation)"
        );

    /// Used to create a hash of the data for the delegateCreateContract function,
    /// that is to be signed by the creator.
    /// @param creator The creator of the contract - must match the address of the signer.
    /// must be incremented by 1 for each new signature.
    function delegateCreateContractHashTypeData(
        address creator,
        string calldata newContractURI,
        string calldata name,
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        bytes[] calldata setupActions
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(DELEGATE_CREATE_TYPEHASH, creator, bytes(newContractURI), bytes(name), defaultRoyaltyConfiguration, setupActions, implementation)
        );

        return _hashTypedDataV4(structHash);
    }

    /// Allows anyone to execute a signature to create a contract on behalf of a creator.
    function delegateCreateContract(
        address payable creator,
        string calldata newContractURI,
        string calldata name,
        ICreatorRoyaltiesControl.RoyaltyConfiguration calldata defaultRoyaltyConfiguration,
        bytes[] calldata setupActions,
        bytes calldata signature
    ) external returns (address newContract) {
        newContract = _createDelegatedContract(creator, newContractURI, name, defaultRoyaltyConfiguration, setupActions, signature);

        _initializeContract(newContract, creator, newContractURI, name, defaultRoyaltyConfiguration, creator, setupActions);
    }

    function _createDelegatedContract(
        address payable creator,
        string calldata newContractURI,
        string calldata name,
        ICreatorRoyaltiesControl.RoyaltyConfiguration calldata defaultRoyaltyConfiguration,
        bytes[] calldata setupActions,
        bytes calldata signature
    ) private returns (address newContract) {
        bytes32 digest = delegateCreateContractHashTypeData(creator, newContractURI, name, defaultRoyaltyConfiguration, setupActions);

        address signatory = ECDSAUpgradeable.recover(digest, signature);

        if (signatory != creator) {
            revert InvalidDelegateSignature();
        }

        // create contract using deterministic address based on the salt (which is the arguments)
        newContract = address(new Zora1155{salt: digest}(address(implementation)));
    }

    /// Used to preview what a delegated created contract's address will be.  That address is deterministic
    function computeDelegateCreatedContractAddress(bytes32 digest) external view returns (address) {
        bytes memory bytecode = type(Zora1155).creationCode;

        bytes32 contractCodeHash = keccak256(abi.encodePacked(bytecode, abi.encode(address(implementation))));

        return Create2Upgradeable.computeAddress(digest, contractCodeHash);
    }

    /// Creates a new contract with a randomly generated new address.
    function _createContract(
        address creator,
        string calldata newContractURI,
        string calldata name,
        ICreatorRoyaltiesControl.RoyaltyConfiguration calldata defaultRoyaltyConfiguration,
        address payable defaultAdmin,
        bytes[] calldata setupActions
    ) private returns (address) {
        address newContract = address(new Zora1155(address(implementation)));

        _initializeContract(newContract, creator, newContractURI, name, defaultRoyaltyConfiguration, defaultAdmin, setupActions);

        return newContract;
    }

    /// Initializes an upgradeable contract.
    function _initializeContract(
        address newContract,
        address creator,
        string calldata newContractURI,
        string calldata name,
        ICreatorRoyaltiesControl.RoyaltyConfiguration calldata defaultRoyaltyConfiguration,
        address payable defaultAdmin,
        bytes[] calldata setupActions
    ) private {
        emit SetupNewContract({
            newContract: newContract,
            creator: creator,
            defaultAdmin: defaultAdmin,
            contractURI: newContractURI,
            name: name,
            defaultRoyaltyConfiguration: defaultRoyaltyConfiguration
        });

        IZoraCreator1155Initializer(newContract).initialize(name, newContractURI, defaultRoyaltyConfiguration, defaultAdmin, setupActions);
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

    function _equals(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(bytes(a)) == keccak256(bytes(b)));
    }
}
