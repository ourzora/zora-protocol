// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IMinter1155} from "../../interfaces/IMinter1155.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {TransferHelperUtils} from "../../utils/TransferHelperUtils.sol";

contract ZoraCreatorFixedPriceSaleStrategy is IMinter1155 {
    struct SalesConfig {
        uint256 pricePerToken;
        uint64 saleStart;
        uint64 saleEnd;
        uint64 maxTokensPerTransaction;
        uint64 maxTokensPerAddress;
    }
    mapping(uint256 => SalesConfig) internal salesConfigs;
    mapping(uint256 => uint256) internal mintedPerAddress;

    function _getKey(address mediaContract, uint256 tokenId) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(mediaContract, tokenId)));
    }

    error WrongValueSent();
    error SaleEnded();
    error SaleHasNotStarted();

    event SetupSale(address mediaContract, uint256 tokenId, SalesConfig salesConfig);
    event RemovedSale(address from, uint256 tokenId);

    function requestMint(
        address,
        uint256 tokenId,
        uint256 quantity,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external view returns (ICreatorCommands.Command[] memory commands) {
        (address mintTo, address fundsRecipient) = abi.decode(minterArguments, (address, address));

        SalesConfig memory config = salesConfigs[_getKey(msg.sender, tokenId)];

        // Check value sent
        if (config.pricePerToken * quantity != ethValueSent) {
            revert WrongValueSent();
        }
        // Check sale end
        if (config.saleEnd > block.timestamp) {
            revert SaleEnded();
        }
        // Check sale start
        if (config.saleStart < block.timestamp) {
            revert SaleHasNotStarted();
        }

        bool shouldTransferFunds = fundsRecipient != address(0);

        // Setup contract commands
        commands = new ICreatorCommands.Command[](shouldTransferFunds ? 2 : 1);

        // Mint command
        commands[0] = ICreatorCommands.Command({method: ICreatorCommands.CreatorActions.MINT, args: abi.encode(mintTo, tokenId, quantity)});

        // If we have a non-default funds recipient for this token
        if (shouldTransferFunds) {
            commands[1] = ICreatorCommands.Command({method: ICreatorCommands.CreatorActions.SEND_ETH, args: abi.encode(fundsRecipient)});
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
