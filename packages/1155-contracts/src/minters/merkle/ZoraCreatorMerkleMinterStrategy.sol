// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Enjoy} from "_imagine/mint/Enjoy.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IMinter1155} from "../../interfaces/IMinter1155.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {SaleStrategy} from "../SaleStrategy.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {SaleCommandHelper} from "../utils/SaleCommandHelper.sol";
import {LimitedMintPerAddress} from "../utils/LimitedMintPerAddress.sol";
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

/// @title ZoraCreatorMerkleMinterStrategy
/// @notice Mints tokens based on a merkle tree, for presales for example
/// @author @iainnash / @tbtstl
contract ZoraCreatorMerkleMinterStrategy is Enjoy, SaleStrategy, LimitedMintPerAddress, IMinterErrors {
    using SaleCommandHelper for ICreatorCommands.CommandSet;

    /// @notice General merkle sale settings
    struct MerkleSaleSettings {
        /// @notice Unix timestamp for the sale start
        uint64 presaleStart;
        /// @notice Unix timestamp for the sale end
        uint64 presaleEnd;
        /// @notice Funds recipient (0 if no different funds recipient than the contract global)
        address fundsRecipient;
        /// @notice Merkle root for
        bytes32 merkleRoot;
    }

    /// @notice Event for sale configuration updated
    event SaleSet(address indexed mediaContract, uint256 indexed tokenId, MerkleSaleSettings merkleSaleSettings);

    /// @notice Storage for allowed merkle settings for the sales configuration
    mapping(address => mapping(uint256 => MerkleSaleSettings)) public allowedMerkles;

    /// @notice ContractURI for contract information with the strategy
    function contractURI() external pure override returns (string memory) {
        return "https://github.com/ourzora/zora-1155-contracts/";
    }

    /// @notice The name of the sale strategy
    function contractName() external pure override returns (string memory) {
        return "Merkle Tree Sale Strategy";
    }

    /// @notice The version of the sale strategy
    function contractVersion() external pure override returns (string memory) {
        return "1.0.0";
    }

    error MerkleClaimsExceeded();

    /// @notice Compiles and returns the commands needed to mint a token using this sales strategy
    /// @param tokenId The token ID to mint
    /// @param quantity The quantity of tokens to mint
    /// @param ethValueSent The amount of ETH sent with the transaction
    /// @param minterArguments The arguments passed to the minter, which should be the address to mint to, the max quantity, the price per token, and the merkle proof
    function requestMint(
        address,
        uint256 tokenId,
        uint256 quantity,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external returns (ICreatorCommands.CommandSet memory commands) {
        (address mintTo, uint256 maxQuantity, uint256 pricePerToken, bytes32[] memory merkleProof) = abi.decode(
            minterArguments,
            (address, uint256, uint256, bytes32[])
        );

        MerkleSaleSettings memory config = allowedMerkles[msg.sender][tokenId];

        // Check sale end
        if (block.timestamp > config.presaleEnd) {
            revert SaleEnded();
        }

        // Check sale start
        if (block.timestamp < config.presaleStart) {
            revert SaleHasNotStarted();
        }

        if (!MerkleProof.verify(merkleProof, config.merkleRoot, keccak256(abi.encode(mintTo, maxQuantity, pricePerToken)))) {
            revert InvalidMerkleProof(mintTo, merkleProof, config.merkleRoot);
        }

        if (maxQuantity > 0) {
            _requireMintNotOverLimitAndUpdate(maxQuantity, quantity, msg.sender, tokenId, mintTo);
        }

        if (quantity * pricePerToken != ethValueSent) {
            revert WrongValueSent();
        }

        // Should transfer funds if funds recipient is set to a non-default address
        bool shouldTransferFunds = config.fundsRecipient != address(0);

        // Setup contract commands
        commands.setSize(shouldTransferFunds ? 2 : 1);

        // Mint command
        commands.mint(mintTo, tokenId, quantity);

        // If we have a non-default funds recipient for this token
        if (shouldTransferFunds) {
            commands.transfer(config.fundsRecipient, ethValueSent);
        }
    }

    /// @notice Sets the sale configuration for a token
    function setSale(uint256 tokenId, MerkleSaleSettings memory merkleSaleSettings) external {
        allowedMerkles[msg.sender][tokenId] = merkleSaleSettings;

        // Emit event for new sale
        emit SaleSet(msg.sender, tokenId, merkleSaleSettings);
    }

    /// @notice Resets the sale configuration for a token
    function resetSale(uint256 tokenId) external override {
        delete allowedMerkles[msg.sender][tokenId];

        // Emit event with empty sale
        emit SaleSet(msg.sender, tokenId, allowedMerkles[msg.sender][tokenId]);
    }

    /// @notice Gets the sale configuration for a token
    /// @param tokenContract address to look up sale for
    /// @param tokenId token ID to look up sale for
    function sale(address tokenContract, uint256 tokenId) external view returns (MerkleSaleSettings memory) {
        return allowedMerkles[tokenContract][tokenId];
    }

    /// @notice IERC165 interface
    /// @param interfaceId intrfaceinterface id to match
    function supportsInterface(bytes4 interfaceId) public pure virtual override(LimitedMintPerAddress, SaleStrategy) returns (bool) {
        return super.supportsInterface(interfaceId) || LimitedMintPerAddress.supportsInterface(interfaceId) || SaleStrategy.supportsInterface(interfaceId);
    }
}
