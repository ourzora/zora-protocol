// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {Ownable2StepUpgradeable} from "../utils/ownable/Ownable2StepUpgradeable.sol";
import {FactoryManagedUpgradeGate} from "../upgrades/FactoryManagedUpgradeGate.sol";
import {Zora1155} from "../proxies/Zora1155.sol";

import {ContractVersionBase} from "../version/ContractVersionBase.sol";

/// @title ZoraCreator1155FactoryImpl
/// @notice Factory contract for creating new ZoraCreator1155 contracts
contract ZoraCreator1155FactoryImpl is IZoraCreator1155Factory, ContractVersionBase, FactoryManagedUpgradeGate, UUPSUpgradeable {
    IZoraCreator1155 public immutable implementation;

    IMinter1155 public immutable merkleMinter;
    IMinter1155 public immutable fixedPriceMinter;

    constructor(IZoraCreator1155 _implementation, IMinter1155 _merkleMinter, IMinter1155 _fixedPriceMinter) initializer {
        implementation = _implementation;
        if (address(implementation) == address(0)) {
            revert Constructor_ImplCannotBeZero();
        }
        merkleMinter = _merkleMinter;
        fixedPriceMinter = _fixedPriceMinter;
    }

    /// @notice The default minters for new 1155 contracts
    function defaultMinters() external view returns (IMinter1155[] memory minters) {
        minters = new IMinter1155[](2);
        minters[0] = fixedPriceMinter;
        minters[1] = merkleMinter;
    }

    function initialize(address _initialOwner) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();

        emit FactorySetup();
    }

    /// @notice Creates a new ZoraCreator1155 contract
    /// @param contractURI The URI for the contract metadata
    /// @param name The name of the contract
    /// @param defaultRoyaltyConfiguration The default royalty configuration for the contract
    /// @param defaultAdmin The default admin for the contract
    /// @param setupActions The actions to perform on the new contract upon initialization
    function createContract(
        string memory contractURI,
        string calldata name,
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        address payable defaultAdmin,
        bytes[] calldata setupActions
    ) external returns (address) {
        IZoraCreator1155 newContract = IZoraCreator1155(address(new Zora1155(address(implementation))));

        newContract.initialize(contractURI, defaultRoyaltyConfiguration, defaultAdmin, setupActions);

        emit SetupNewContract({
            newContract: address(newContract),
            creator: msg.sender,
            defaultAdmin: defaultAdmin,
            contractURI: contractURI,
            name: name,
            defaultRoyaltyConfiguration: defaultRoyaltyConfiguration
        });

        return address(newContract);
    }

    ///                                                          ///
    ///                         MANAGER UPGRADE                  ///
    ///                                                          ///

    /// @notice Ensures the caller is authorized to upgrade the contract
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal override onlyOwner {}
}
