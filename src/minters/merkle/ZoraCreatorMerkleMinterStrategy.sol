// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IMinter1155} from "../../interfaces/IMinter1155.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {TransferHelperUtils} from "../../utils/TransferHelperUtils.sol";
import {SaleStrategy} from "../SaleStrategy.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {SaleCommandHelper} from "../SaleCommandHelper.sol";

/// @title ZoraCreatorMerkleMinterStrategy
/// notice Mints tokens based on a merkle tree, for presales for example
contract ZoraCreatorMerkleMinterStrategy is SaleStrategy {
    using SaleCommandHelper for ICreatorCommands.CommandSet;
    struct MerkleSaleSettings {
        uint64 presaleStart;
        uint64 presaleEnd;
        address fundsRecipient;
        bytes32 merkleRoot;
    }

    event SaleSet(address indexed mediaContract, uint256 indexed tokenId, MerkleSaleSettings merkleSaleSettings);

    mapping(bytes32 => MerkleSaleSettings) public allowedMerkles;

    mapping(bytes32 => uint256) public mintedPerAddress;

    error SaleEnded();
    error SaleHasNotStarted();
    error MintedTooManyForAddress();
    error WrongValueSent();
    error InvalidMerkleProof(address mintTo, bytes32[] merkleProof, bytes32 merkleRoot);

    function contractURI() external pure override returns (string memory) {
        // TODO(iain): Add contract URI configuration json for front-end
        return "";
    }

    /// @notice The name of the sale strategy
    function contractName() external pure override returns (string memory) {
        return "Merkle Tree Sale Strategy";
    }

    /// @notice The version of the sale strategy
    function contractVersion() external pure override returns (string memory) {
        return "0.0.1";
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

        MerkleSaleSettings memory config = allowedMerkles[_getKey(msg.sender, tokenId)];

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
            bytes32 key = keccak256(abi.encode(msg.sender, tokenId, mintTo));
            mintedPerAddress[key] += quantity;
            if (mintedPerAddress[key] > maxQuantity) {
                revert MintedTooManyForAddress();
            }
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
        allowedMerkles[_getKey(msg.sender, tokenId)] = merkleSaleSettings;

        // Emit event for new sale
        emit SaleSet(msg.sender, tokenId, merkleSaleSettings);
    }

    /// @notice Resets the sale configuration for a token
    function resetSale(uint256 tokenId) external override {
        delete allowedMerkles[_getKey(msg.sender, tokenId)];

        // Emit event with empty sale
        emit SaleSet(msg.sender, tokenId, allowedMerkles[_getKey(msg.sender, tokenId)]);
    }

    /// @notice Gets the sale configuration for a token
    function sale(address tokenContract, uint256 tokenId) external view returns (MerkleSaleSettings memory) {
        return allowedMerkles[_getKey(tokenContract, tokenId)];
    }
}
