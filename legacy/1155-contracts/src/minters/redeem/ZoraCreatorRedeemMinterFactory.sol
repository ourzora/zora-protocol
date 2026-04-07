// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {Enjoy} from "_imagine/mint/Enjoy.sol";

import {IContractMetadata} from "../../interfaces/IContractMetadata.sol";
import {IVersionedContract} from "@zoralabs/shared-contracts/interfaces/IVersionedContract.sol";
import {IMinter1155} from "../../interfaces/IMinter1155.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {ZoraCreatorRedeemMinterStrategy} from "./ZoraCreatorRedeemMinterStrategy.sol";
import {IZoraCreator1155} from "../../interfaces/IZoraCreator1155.sol";
import {SharedBaseConstants} from "../../shared/SharedBaseConstants.sol";
import {IMinterErrors} from "../../interfaces/IMinterErrors.sol";

/*


             ░░░░░░░░░░░░░░              
        ░░▒▒░░░░░░░░░░░░░░░░░░░░        
      ░░▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░      
    ░░▒▒▒▒░░░░░░░░░░░░░░    ░░░░░░░░    
   ░▓▓▒▒▒▒░░░░░░░░░░░░        ░░░░░░░    
  ░▓▓▓▒▒▒▒░░░░░░░░░░░░        ░░░░░░░░  
  ░▓▓▓▒▒▒▒░░░░░░░░░░░░░░    ░░░░░░░░░░  
  ░▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░  
  ░▓▓▓▓▓▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░  
   ░▓▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░  
    ░░▓▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░    
    ░░▓▓▓▓▓▓▒▒▒▒▒▒▒▒░░░░░░░░░▒▒▒▒▒░░    
      ░░▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░      
          ░░▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░░          

               OURS TRULY,


    github.com/ourzora/zora-1155-contracts

*/

/// @title ZoraCreatorRedeemMinterFactory
/// @notice A factory for ZoraCreatorRedeemMinterStrategy contracts
/// @author @jgeary
contract ZoraCreatorRedeemMinterFactory is Enjoy, IContractMetadata, SharedBaseConstants, IVersionedContract, IMinter1155, IMinterErrors {
    bytes4 constant LEGACY_ZORA_IMINTER1155_INTERFACE_ID = 0x6467a6fc;
    address public immutable zoraRedeemMinterImplementation;

    event RedeemMinterDeployed(address indexed creatorContract, address indexed minterContract);

    constructor() {
        zoraRedeemMinterImplementation = address(new ZoraCreatorRedeemMinterStrategy());
    }

    /// @notice Factory contract URI
    function contractURI() external pure override returns (string memory) {
        return "https://github.com/ourzora/zora-1155-contracts/";
    }

    /// @notice Factory contract name
    function contractName() external pure override returns (string memory) {
        return "Redeem Minter Factory";
    }

    /// @notice Factory contract version
    function contractVersion() external pure override returns (string memory) {
        return "1.1.0";
    }

    /// @notice No-op function for IMinter1155 compatibility
    function requestMint(
        address sender,
        uint256 tokenId,
        uint256 quantity,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external returns (ICreatorCommands.CommandSet memory commands) {}

    /// @notice IERC165 interface support
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IMinter1155).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @notice Deploys a new ZoraCreatorRedeemMinterStrategy for caller ZoraCreator1155 contract if none exists
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

    /// @notice Returns deterministic address of a ZoraCreatorRedeemMinterStrategy for a given ZoraCreator1155 contract
    /// @param _creatorContract ZoraCreator1155 contract address
    /// @return Address of ZoraCreatorRedeemMinterStrategy
    function predictMinterAddress(address _creatorContract) public view returns (address) {
        return Clones.predictDeterministicAddress(zoraRedeemMinterImplementation, keccak256(abi.encode(_creatorContract)), address(this));
    }

    /// @notice Returns true if a ZoraCreatorRedeemMinterStrategy has been deployed for a given ZoraCreator1155 contract
    /// @param _creatorContract ZoraCreator1155 contract address
    /// @return True if a ZoraCreatorRedeemMinterStrategy has been deployed for a given ZoraCreator1155 contract
    function doesRedeemMinterExistForCreatorContract(address _creatorContract) public view returns (bool) {
        return predictMinterAddress(_creatorContract).code.length > 0;
    }

    /// @notice Returns address of deployed ZoraCreatorRedeemMinterStrategy for a given ZoraCreator1155 contract
    /// @param _creatorContract ZoraCreator1155 contract address
    /// @return Address of deployed ZoraCreatorRedeemMinterStrategy
    function getDeployedRedeemMinterForCreatorContract(address _creatorContract) external view returns (address) {
        address minter = predictMinterAddress(_creatorContract);
        if (minter.code.length == 0) {
            revert MinterContractDoesNotExist();
        }
        return minter;
    }
}
