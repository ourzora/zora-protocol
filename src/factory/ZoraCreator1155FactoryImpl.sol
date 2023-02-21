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
import {ZoraCreator1155Proxy} from "../proxies/ZoraCreator1155Proxy.sol";

contract ZoraCreator1155FactoryImpl is IZoraCreator1155Factory, FactoryManagedUpgradeGate, UUPSUpgradeable {
    IZoraCreator1155 public immutable implementation;

    IMinter1155 private immutable merkleMinter;
    IMinter1155 private immutable fixedPriceMinter;

    function contractVersion() external pure override returns (string memory) {
        return "0.0.1";
    }

    constructor(
        IZoraCreator1155 _implementation,
        IMinter1155 _merkleMinter,
        IMinter1155 _fixedPriceMinter
    ) initializer {
        implementation = _implementation;
        if (address(implementation) == address(0)) {
            revert Constructor_ImplCannotBeZero();
        }
        merkleMinter = _merkleMinter;
        fixedPriceMinter = _fixedPriceMinter;
    }

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

    function createContract(
        string memory contractURI,
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory defaultRoyaltyConfiguration,
        address defaultAdmin,
        bytes[] calldata setupActions
    ) external returns (address) {
        IZoraCreator1155 newContract = IZoraCreator1155(address(new ZoraCreator1155Proxy(address(implementation))));

        newContract.initialize(contractURI, defaultRoyaltyConfiguration, defaultAdmin, setupActions);

        emit SetupNewContract({
            newContract: address(newContract),
            creator: msg.sender,
            defaultAdmin: defaultAdmin,
            contractURI: contractURI,
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
