// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IMinter1155} from "../../interfaces/IMinter1155.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {TransferHelperUtils} from "../../utils/TransferHelperUtils.sol";
import {SaleStrategy} from "../SaleStrategy.sol";
import {SaleCommandHelper} from "../SaleCommandHelper.sol";

/// @title ZoraCreatorFixedPriceSaleStrategy
/// @notice A sale strategy for ZoraCreator that allows for fixed price sales over a given time period
contract ZoraCreatorFixedPriceSaleStrategy is SaleStrategy {
    struct SalesConfig {
        uint64 saleStart;
        uint64 saleEnd;
        uint64 maxTokensPerAddress;
        uint96 pricePerToken;
        address fundsRecipient;
    }
    mapping(bytes32 => SalesConfig) internal salesConfigs;
    mapping(bytes32 => uint256) internal mintedPerAddress;

    using SaleCommandHelper for ICreatorCommands.CommandSet;

    function contractURI() external pure override returns (string memory) {
        // TODO(iain): Add contract URI configuration json for front-end
        return "";
    }

    /// @notice The name of the sale strategy
    function contractName() external pure override returns (string memory) {
        return "Fixed Price Sale Strategy";
    }

    /// @notice The version of the sale strategy
    function contractVersion() external pure override returns (string memory) {
        return "0.0.1";
    }

    error WrongValueSent();
    error SaleEnded();
    error SaleHasNotStarted();
    error MintedTooManyForAddress();

    event SaleSet(address mediaContract, uint256 tokenId, SalesConfig salesConfig);

    /// @notice Compiles and returns the commands needed to mint a token using this sales strategy
    /// @param tokenId The token ID to mint
    /// @param quantity The quantity of tokens to mint
    /// @param ethValueSent The amount of ETH sent with the transaction
    /// @param minterArguments The arguments passed to the minter, which should be the address to mint to
    function requestMint(
        address,
        uint256 tokenId,
        uint256 quantity,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external returns (ICreatorCommands.CommandSet memory commands) {
        address mintTo = abi.decode(minterArguments, (address));

        SalesConfig memory config = salesConfigs[_getKey(msg.sender, tokenId)];

        // If sales config does not exist this first check will always fail.

        // Check sale end
        if (block.timestamp > config.saleEnd) {
            revert SaleEnded();
        }

        // Check sale start
        if (block.timestamp < config.saleStart) {
            revert SaleHasNotStarted();
        }

        // Check value sent
        if (config.pricePerToken * quantity != ethValueSent) {
            revert WrongValueSent();
        }

        // Check minted per address limit
        if (config.maxTokensPerAddress > 0) {
            bytes32 key = keccak256(abi.encode(msg.sender, tokenId, mintTo));
            mintedPerAddress[key] += quantity;
            if (mintedPerAddress[key] > config.maxTokensPerAddress) {
                revert MintedTooManyForAddress();
            }
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

    /// @notice Sets the sale config for a given token
    function setSale(uint256 tokenId, SalesConfig memory salesConfig) external {
        salesConfigs[_getKey(msg.sender, tokenId)] = salesConfig;

        // Emit event
        emit SaleSet(msg.sender, tokenId, salesConfig);
    }

    /// @notice Deletes the sale config for a given token
    function resetSale(uint256 tokenId) external override {
        delete salesConfigs[_getKey(msg.sender, tokenId)];

        // Deleted sale emit event
        emit SaleSet(msg.sender, tokenId, salesConfigs[_getKey(msg.sender, tokenId)]);
    }

    /// @notice Returns the sale config for a given token
    function sale(address tokenContract, uint256 tokenId) external view returns (SalesConfig memory) {
        return salesConfigs[_getKey(tokenContract, tokenId)];
    }
}
