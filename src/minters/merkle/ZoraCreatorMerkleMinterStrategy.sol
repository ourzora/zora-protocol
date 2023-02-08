// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IMinter1155} from "../../interfaces/IMinter1155.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {TransferHelperUtils} from "../../utils/TransferHelperUtils.sol";
import {SaleStrategy} from "../SaleStrategy.sol";

contract ZoraCreatorMerkleMinterStrategy is SaleStrategy {
    struct MerkleSaleSettings {
        uint64 presaleStart;
        uint64 presaleEnd;
        address fundsRecipient;
        bytes32 merkleRoot;
    }

    event SaleSetup(address sender, uint256 tokenId, MerkleSaleSettings merkleSaleSettings);

    mapping(uint256 => MerkleSaleSettings) allowedMerkles;

    mapping(bytes32 => uint256) internal mintedPerAddress;

    error MintedTooManyForAddress();

    error IncorrectValueSent(uint256 tokenId, uint256 quantity, uint256 ethValueSent);
    error InvalidMerkleProof(address mintTo, bytes32[] merkleProof, bytes32 merkleRoot);

    function contractURI() external pure override returns (string memory) {
        // TODO(iain): Add contract URI configuration json for front-end
        return "";
    }

    function contractName() external pure override returns (string memory) {
        return "Merkle Tree Sale Strategy";
    }

    function contractVersion() external pure override returns (string memory) {
        return "0.0.1";
    }

    error MerkleClaimsExceeded();

    event SetupMerkleRoot(address mediaContract, uint256 tokenId, bytes32 merkleRoot);
    event RemovedMerkleRoot(address mediaContract, uint256 tokenId);

    function requestMint(
        address,
        uint256 tokenId,
        uint256 quantity,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external returns (ICreatorCommands.Command[] memory commands) {
        (address mintTo, uint256 maxQuantity, uint256 pricePerToken, bytes32[] memory merkleProof) = abi.decode(
            minterArguments,
            (address, uint256, uint256, bytes32[])
        );

        MerkleSaleSettings memory config = allowedMerkles[_getKey(msg.sender, tokenId)];

        if (!MerkleProof.verify(merkleProof, config.merkleRoot, keccak256(abi.encode(mintTo, maxQuantity, pricePerToken)))) {
            revert InvalidMerkleProof(mintTo, merkleProof, config.merkleRoot);
        }

        if (maxQuantity > 0) {
            bytes32 key = keccak256(abi.encode(msg.sender, tokenId, mintTo));
            mintedPerAddress[key] += quantity;
            if (maxQuantity > mintedPerAddress[key]) {
                revert MintedTooManyForAddress();
            }
        }

        if (quantity * pricePerToken != ethValueSent) {
            revert IncorrectValueSent(tokenId, quantity * pricePerToken, ethValueSent);
        }

        // Should transfer funds if funds recipient is set to a non-default address
        bool shouldTransferFunds = config.fundsRecipient != address(0);

        // Setup contract commands
        commands = new ICreatorCommands.Command[](shouldTransferFunds ? 2 : 1);

        // Mint command
        commands[0] = ICreatorCommands.Command({method: ICreatorCommands.CreatorActions.MINT, args: abi.encode(mintTo, tokenId, quantity)});

        // If we have a non-default funds recipient for this token
        if (shouldTransferFunds) {
            commands[1] = ICreatorCommands.Command({method: ICreatorCommands.CreatorActions.SEND_ETH, args: abi.encode(config.fundsRecipient, ethValueSent)});
        }
    }

    function setupSale(uint256 tokenId, MerkleSaleSettings memory merkleSaleSettings) external {
        allowedMerkles[_getKey(msg.sender, tokenId)] = merkleSaleSettings;

        // Emit event
        emit SaleSetup(msg.sender, tokenId, merkleSaleSettings);
    }

    function resetSale(uint256 tokenId) external override {
        delete allowedMerkles[_getKey(msg.sender, tokenId)];

        // Removed sale confirmation
        emit SaleRemoved(msg.sender, tokenId);
    }
}
