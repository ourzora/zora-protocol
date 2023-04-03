// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

import {IVersionedContract} from "../../interfaces/IVersionedContract.sol";
import {IMinter1155} from "../../interfaces/IMinter1155.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {ZoraCreatorRedeemMinterStrategy} from "./ZoraCreatorRedeemMinterStrategy.sol";
import {IZoraCreator1155} from "../../interfaces/IZoraCreator1155.sol";
import {SharedBaseConstants} from "../../shared/SharedBaseConstants.sol";
import {ZoraCreatorRedeemMinterFactory} from "../../minters/redeem/ZoraCreatorRedeemMinterFactory.sol";

contract ZoraCreatorRedeemMinterFactory is SharedBaseConstants, IVersionedContract, IMinter1155 {
    address public immutable zoraRedeemMinterImplementation;

    event RedeemMinterDeployed(address indexed creatorContract, address indexed minterContract);

    error CallerNotZoraCreator1155();
    error MinterContractAlreadyExists();
    error MinterContractDoesNotExist();

    constructor() {
        zoraRedeemMinterImplementation = address(new ZoraCreatorRedeemMinterStrategy());
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
        return interfaceId == type(IMinter1155).interfaceId || interfaceId == bytes4(0x00000000) || interfaceId == type(IERC165).interfaceId;
    }

    function createMinterIfNoneExists() external {
        if (!IERC165(msg.sender).supportsInterface(type(IZoraCreator1155).interfaceId)) {
            revert CallerNotZoraCreator1155();
        }
        if (doesRedeemMinterExistForCreatorContract(msg.sender)) {
            return;
        }
        address minter = Clones.cloneDeterministic(zoraRedeemMinterImplementation, keccak256(abi.encode(msg.sender)));
        ZoraCreatorRedeemMinterStrategy(minter).initialize(msg.sender);

        emit RedeemMinterDeployed(msg.sender, minter);
    }

    function predictMinterAddress(address _creatorContract) public view returns (address) {
        return Clones.predictDeterministicAddress(zoraRedeemMinterImplementation, keccak256(abi.encode(_creatorContract)), address(this));
    }

    function doesRedeemMinterExistForCreatorContract(address _creatorContract) public view returns (bool) {
        return address(predictMinterAddress(_creatorContract)).code.length > 0;
    }

    function getDeployedRedeemMinterForCreatorContract(address _creatorContract) external view returns (address) {
        address minter = predictMinterAddress(_creatorContract);
        if (minter.code.length == 0) {
            revert MinterContractDoesNotExist();
        }
        return minter;
    }
}
