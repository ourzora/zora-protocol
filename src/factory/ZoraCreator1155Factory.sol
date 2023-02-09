// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {IZoraCreator1155} from "../interfaces/IZoraCreator1155.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {Ownable2StepUpgradeable} from "../utils/ownable/Ownable2StepUpgradeable.sol";
import {FactoryManagedUpgradeGate} from "../upgrades/FactoryManagedUpgradeGate.sol";
import {ZoraCreator1155Proxy} from "../proxies/ZoraCreator1155Proxy.sol";

contract ZoraCreator1155Factory is IZoraCreator1155Factory, FactoryManagedUpgradeGate, UUPSUpgradeable {
    IZoraCreator1155 public immutable implementation;

    constructor(IZoraCreator1155 _implementation) initializer {
        implementation = _implementation;
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
        // TODO: figure out how to add multicall here to setup contract
        newContract.initialize({
            contractURI: contractURI,
            defaultRoyaltyConfiguration: defaultRoyaltyConfiguration,
            defaultAdmin: defaultAdmin,
            setupActions: setupActions
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
