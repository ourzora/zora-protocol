// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Enjoy} from "_imagine/mint/Enjoy.sol";
import {IMinter1155} from "../../interfaces/IMinter1155.sol";
import {IZoraCreator1155} from "../../interfaces/IZoraCreator1155.sol";
import {ICreatorCommands} from "../../interfaces/ICreatorCommands.sol";
import {SaleStrategy} from "../SaleStrategy.sol";
import {SaleCommandHelper} from "../utils/SaleCommandHelper.sol";
import {LimitedMintPerAddress} from "../utils/LimitedMintPerAddress.sol";
import {IMinterErrors} from "../../interfaces/IMinterErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

/// @title ERC20CreatorFixedPriceSaleStrategy
/// @notice A sale strategy for ZoraCreator that allows for ERC20 fixed price sales over a given time period
/// @author @iainnash / @tbtstl / @sweetman
contract ERC20CreatorFixedPriceSaleStrategy is Enjoy, SaleStrategy, LimitedMintPerAddress, IMinterErrors {
    struct SalesConfig {
        /// @notice Unix timestamp for the sale start
        uint64 saleStart;
        /// @notice Unix timestamp for the sale end
        uint64 saleEnd;
        /// @notice Max tokens that can be minted for an address, 0 if unlimited
        uint64 maxTokensPerAddress;
        /// @notice Price per token in ERC20 amount.
        uint96 pricePerToken;
        /// @notice Funds recipient (0 if no different funds recipient than the contract global)
        address fundsRecipient;
        /// @notice ERC20 address (0 if ETH)
        address erc20Address;
    }

    // target -> tokenId -> settings
    mapping(address => mapping(uint256 => SalesConfig)) internal salesConfigs;

    using SaleCommandHelper for ICreatorCommands.CommandSet;

    function contractURI() external pure override returns (string memory) {
        return "https://github.com/ourzora/zora-1155-contracts/";
    }

    /// @notice The name of the sale strategy
    function contractName() external pure override returns (string memory) {
        return "Fixed Price Sale Strategy";
    }

    /// @notice The version of the sale strategy
    function contractVersion() external pure override returns (string memory) {
        return "1.1.0";
    }

    event SaleSet(address indexed mediaContract, uint256 indexed tokenId, SalesConfig salesConfig);
    event MintComment(address indexed sender, address indexed tokenContract, uint256 indexed tokenId, uint256 quantity, string comment);

    /// @notice mint using ERC20 calls.
    /// @param target The target drop
    /// @param tokenId The token ID to mint
    /// @param quantity The quantity of tokens to mint
    /// @param minterArguments The arguments passed to the minter, which should be the address to mint to
    function requestMint(
        address target,
        uint256 tokenId,
        uint256 quantity,
        uint256,
        bytes calldata minterArguments
    ) external returns (ICreatorCommands.CommandSet memory commands) {
        address mintTo;
        string memory comment = "";
        if (minterArguments.length == 32) {
            mintTo = abi.decode(minterArguments, (address));
        } else {
            (mintTo, comment) = abi.decode(minterArguments, (address, string));
        }

        SalesConfig storage config = salesConfigs[target][tokenId];

        // If sales config does not exist this first check will always fail.

        // Check sale end
        if (block.timestamp > config.saleEnd) {
            revert SaleEnded();
        }

        // Check sale start
        if (block.timestamp < config.saleStart) {
            revert SaleHasNotStarted();
        }

        // Check USDC approval amount
        if (config.pricePerToken * quantity > IERC20(config.erc20Address).allowance(msg.sender, address(this))) {
            revert WrongValueSent();
        }
        
        // Check minted per address limit
        if (config.maxTokensPerAddress > 0) {
            _requireMintNotOverLimitAndUpdate(config.maxTokensPerAddress, quantity, target, tokenId, mintTo);
        }

        bool shouldTransferFunds = config.fundsRecipient != address(0);

        // Mint command
        IZoraCreator1155(target).adminMint(mintTo, tokenId, quantity, bytes(""));


        if (bytes(comment).length > 0) {
            emit MintComment(mintTo, target, tokenId, quantity, comment);
        }

        // Should transfer funds if funds recipient is set to a non-default address
        if (shouldTransferFunds) {
            IERC20(config.erc20Address).transferFrom(msg.sender, config.fundsRecipient, config.pricePerToken * quantity);
        }
    }

    /// @notice Sets the sale config for a given token
    function setSale(uint256 tokenId, SalesConfig memory salesConfig) external {
        salesConfigs[msg.sender][tokenId] = salesConfig;

        // Emit event
        emit SaleSet(msg.sender, tokenId, salesConfig);
    }

    /// @notice Deletes the sale config for a given token
    function resetSale(uint256 tokenId) external override {
        delete salesConfigs[msg.sender][tokenId];

        // Deleted sale emit event
        emit SaleSet(msg.sender, tokenId, salesConfigs[msg.sender][tokenId]);
    }

    /// @notice Returns the sale config for a given token
    function sale(address tokenContract, uint256 tokenId) external view returns (SalesConfig memory) {
        return salesConfigs[tokenContract][tokenId];
    }

    function supportsInterface(bytes4 interfaceId) public pure virtual override(LimitedMintPerAddress, SaleStrategy) returns (bool) {
        return super.supportsInterface(interfaceId) || LimitedMintPerAddress.supportsInterface(interfaceId) || SaleStrategy.supportsInterface(interfaceId);
    }
}
