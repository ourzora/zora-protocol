// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IMinter1155} from "../../interfaces/IMinter1155.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {TransferHelperUtils} from "../../utils/TransferHelperUtils.sol";
import {SaleStrategy} from "../SaleStrategy.sol";
import {SaleCommandHelper} from "../SaleCommandHelper.sol";

contract ZoraCreatorFixedPriceSaleStrategy is SaleStrategy {
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

    using SaleCommandHelper for ICreatorCommands.CommandSet;

    function contractURI() external pure override returns (string memory) {
        // TODO(iain): Add contract URI configuration json for front-end
        return "";
    }

    function contractName() external pure override returns (string memory) {
        return "Fixed Price Sale Strategy";
    }

    function contractVersion() external pure override returns (string memory) {
        return "0.0.1";
    }

    error WrongValueSent();
    error SaleEnded();
    error SaleHasNotStarted();
    error MintedTooManyForAddress();
    error TooManyTokensInOneTxn();

    event SaleSetup(address mediaContract, uint256 tokenId, SalesConfig salesConfig);

    function requestMint(
        address,
        uint256 tokenId,
        uint256 quantity,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external returns (ICreatorCommands.CommandSet memory commands) {
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

        bool shouldTransferFunds = config.fundsRecipient != address(0);
        commands.setSize(shouldTransferFunds ? 2 : 1);

        // Mint command
        commands.mint(mintTo, tokenId, quantity);

        // Should transfer funds if funds recipient is set to a non-default address
        if (shouldTransferFunds) {
            commands.transfer(config.fundsRecipient, ethValueSent);
        }
    }

    function setupSale(uint256 tokenId, SalesConfig memory salesConfig) external {
        salesConfigs[_getKey(msg.sender, tokenId)] = salesConfig;

        // Emit event
        emit SaleSetup(msg.sender, tokenId, salesConfig);
    }

    function resetSale(uint256 tokenId) external override {
        delete salesConfigs[_getKey(msg.sender, tokenId)];

        // Removed sale confirmation
        emit SaleRemoved(msg.sender, tokenId);
    }
}
