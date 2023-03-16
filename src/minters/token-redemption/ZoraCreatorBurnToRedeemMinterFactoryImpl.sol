// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IVersionedContract} from "../../interfaces/IVersionedContract.sol";
import {IMinter1155} from "../../interfaces/IMinter1155.sol";
import {ZoraCreatorBurnToRedeemMinterStrategy} from "./ZoraCreatorBurnToRedeemMinterStrategy.sol";
import {Ownable2StepUpgradeable} from "../../utils/ownable/Ownable2StepUpgradeable.sol";
import {IZoraCreator1155} from "../../interfaces/IZoraCreator1155.sol";
import {SharedBaseConstants} from "../../shared/SharedBaseConstants.sol";

contract ZoraCreatorBurnToRedeemMinterFactoryImpl is UUPSUpgradeable, Ownable2StepUpgradeable, SharedBaseConstants, IVersionedContract {
    struct MinterContract {
        address deployedAddress;
        string version;
    }

    mapping(address => MinterContract) public deployedMinterContractForCreatorContract;

    event MinterCreated(address minter);

    error ContractNotZoraCreator1155();
    error CallerNotAdmin();
    error MinterContractAlreadyExists();
    error MinterContractDoesNotExist();

    function initialize(address _initialOwner) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();
    }

    function contractVersion() external pure override returns (string memory) {
        return "0.0.1";
    }

    function createMinter(address _creatorContract, bytes32 _salt) external returns (address) {
        if (!IERC165(_creatorContract).supportsInterface(type(IZoraCreator1155).interfaceId)) {
            revert ContractNotZoraCreator1155();
        }
        if (!IZoraCreator1155(_creatorContract).isAdminOrRole(msg.sender, CONTRACT_BASE_ID, IZoraCreator1155(_creatorContract).PERMISSION_BIT_ADMIN())) {
            revert CallerNotAdmin();
        }
        if (
            keccak256(abi.encodePacked(deployedMinterContractForCreatorContract[_creatorContract].version)) ==
            keccak256(abi.encodePacked(this.contractVersion()))
        ) {
            revert MinterContractAlreadyExists();
        }

        ZoraCreatorBurnToRedeemMinterStrategy minter = new ZoraCreatorBurnToRedeemMinterStrategy{salt: _salt}(_creatorContract);
        deployedMinterContractForCreatorContract[_creatorContract].deployedAddress = address(minter);
        deployedMinterContractForCreatorContract[_creatorContract].version = this.contractVersion();

        emit MinterCreated(address(minter));

        return address(minter);
    }

    function predictMinterAddress(address _creatorContract, bytes32 _salt) external view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                _salt,
                keccak256(abi.encodePacked(type(ZoraCreatorBurnToRedeemMinterStrategy).creationCode, abi.encode(_creatorContract)))
            )
        );

        return address(uint160(uint(hash)));
    }

    function getDeployedMinterForCreatorContract(address _creatorContract) external view returns (address) {
        if (deployedMinterContractForCreatorContract[_creatorContract].deployedAddress == address(0)) {
            revert MinterContractDoesNotExist();
        }
        return deployedMinterContractForCreatorContract[_creatorContract].deployedAddress;
    }

    ///                                                          ///
    ///                         MANAGER UPGRADE                  ///
    ///                                                          ///

    /// @notice Ensures the caller is authorized to upgrade the contract
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal override onlyOwner {}
}
