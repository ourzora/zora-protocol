// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IMinter1155} from "../../interfaces/IMinter1155.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {TransferHelperUtils} from "../../utils/TransferHelperUtils.sol";

contract ZoraCreatorFixedPriceSaleStrategy is IMinter1155 {
    struct SalesConfig {
        uint64 saleStart;
        uint64 saleEnd;
        uint64 maxTokensPerTransaction;
        uint64 maxTokensPerAddress;
        uint96 pricePerToken;
        address fundsRecipient;
    }
    mapping(uint256 => SalesConfig) internal salesConfigs;
    mapping(bytes32 => uint256) internal mintedPerAddress;

    function _getKey(address mediaContract, uint256 tokenId) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(mediaContract, tokenId)));
    }

    error WrongValueSent();
    error SaleEnded();
    error SaleHasNotStarted();
    error MintedTooManyForAddress();
    error TooManyTokensInOneTxn();

    event SetupSale(address mediaContract, uint256 tokenId, SalesConfig salesConfig);
    event RemovedSale(address from, uint256 tokenId);

    function requestMint(
        address,
        uint256 tokenId,
        uint256 quantity,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external returns (ICreatorCommands.Command[] memory commands) {
        address mintTo = abi.decode(minterArguments, (address));

        SalesConfig memory config = salesConfigs[_getKey(msg.sender, tokenId)];

        // Check value sent
        if (config.pricePerToken * quantity != ethValueSent) {
            revert WrongValueSent();
        }
        // Check sale end
        if (block.timestamp > config.saleEnd) {
            revert SaleEnded();
        }
        // Check sale start
        if (block.timestamp < config.saleStart) {
            revert SaleHasNotStarted();
        }
        // Check minted per address limit
        if (config.maxTokensPerAddress > 0) {
            bytes32 key = keccak256(abi.encode(msg.sender, tokenId, mintTo));
            mintedPerAddress[key] += quantity;
            if (config.maxTokensPerAddress > mintedPerAddress[key]) {
                revert MintedTooManyForAddress();
            }
        }
        // Check minted per txn limit
        if (config.maxTokensPerTransaction > 0 && quantity > config.maxTokensPerTransaction) {
            revert TooManyTokensInOneTxn();
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

    function setupSale(uint256 tokenId, SalesConfig memory salesConfig) external {
        salesConfigs[_getKey(msg.sender, tokenId)] = salesConfig;

        // Emit event
        emit SetupSale(msg.sender, tokenId, salesConfig);
    }

    function resetSale(uint256 tokenId) external {
        delete salesConfigs[_getKey(msg.sender, tokenId)];

        // Removed sale confirmation
        emit RemovedSale(msg.sender, tokenId);
    }
}
