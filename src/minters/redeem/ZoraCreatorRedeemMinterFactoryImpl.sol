// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ClonesUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import {IERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/interfaces/IERC165Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IVersionedContract} from "../../interfaces/IVersionedContract.sol";
import {IMinter1155} from "../../interfaces/IMinter1155.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {ZoraCreatorRedeemMinterStrategy} from "./ZoraCreatorRedeemMinterStrategy.sol";
import {Ownable2StepUpgradeable} from "../../utils/ownable/Ownable2StepUpgradeable.sol";
import {IZoraCreator1155} from "../../interfaces/IZoraCreator1155.sol";
import {SharedBaseConstants} from "../../shared/SharedBaseConstants.sol";

contract ZoraCreatorRedeemMinterFactoryImpl is UUPSUpgradeable, Ownable2StepUpgradeable, SharedBaseConstants, IVersionedContract, IMinter1155 {
    struct MinterContract {
        address deployedAddress;
        string version;
    }

    address public immutable zoraRedeemMinterImplementation;

    mapping(address => MinterContract) public deployedMinterContractForCreatorContract;

    event RedeemMinterDeployed(address indexed creatorContract, address indexed minterContract);

    error CallerNotZoraCreator1155();
    error MinterContractAlreadyExists();
    error MinterContractDoesNotExist();

    // TODO: if this approach is the one used make this an intiailizer
    constructor() {
        zoraRedeemMinterImplementation = address(new ZoraCreatorRedeemMinterStrategy());
    }

    function initialize(address _initialOwner) public initializer {
        __Ownable_init(_initialOwner);
        __UUPSUpgradeable_init();
    }

    function contractVersion() external pure override returns (string memory) {
        return "0.0.1";
    }

    function requestMint(
        address sender,
        uint256 tokenId,
        uint256 quantity,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external returns (ICreatorCommands.CommandSet memory commands) {}

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IMinter1155).interfaceId || interfaceId == type(IERC165Upgradeable).interfaceId;
    }

    function createMinter() external {
        if (!IERC165Upgradeable(msg.sender).supportsInterface(type(IZoraCreator1155).interfaceId)) {
            revert CallerNotZoraCreator1155();
        }
        if (keccak256(abi.encodePacked(deployedMinterContractForCreatorContract[msg.sender].version)) == keccak256(abi.encodePacked(this.contractVersion()))) {
            revert MinterContractAlreadyExists();
        }

        address minter = ClonesUpgradeable.cloneDeterministic(zoraRedeemMinterImplementation, keccak256(abi.encode(msg.sender)));
        ZoraCreatorRedeemMinterStrategy(minter).initialize(msg.sender);
        deployedMinterContractForCreatorContract[msg.sender].deployedAddress = minter;
        deployedMinterContractForCreatorContract[msg.sender].version = this.contractVersion();

        emit RedeemMinterDeployed(msg.sender, minter);
    }

    function predictMinterAddress(address _creatorContract) external view returns (address) {
        return ClonesUpgradeable.predictDeterministicAddress(zoraRedeemMinterImplementation, keccak256(abi.encode(_creatorContract)), address(this));
    }

    function doesRedeemMinterExistForCreatorContract(address _creatorContract) external view returns (bool) {
        return deployedMinterContractForCreatorContract[_creatorContract].deployedAddress != address(0);
    }

    function getDeployedRedeemMinterForCreatorContract(address _creatorContract) external view returns (address) {
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
