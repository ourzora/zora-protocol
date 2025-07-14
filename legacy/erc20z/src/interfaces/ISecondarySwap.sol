// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

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


*/

interface ISecondarySwap {
    enum SecondaryType {
        /// @notice Buy 1155 tokens event
        BUY,
        /// @notice Sell 1155 tokens event
        SELL
    }

    /// @notice SecondaryBuy Event
    /// @param msgSender The sender of the message
    /// @param recipient The recipient of the 1155 tokens bought
    /// @param erc20zAddress The ERC20Z address
    /// @param amountETHSold The amount of ETH sold
    /// @param num1155Purchased The number of 1155 tokens purchased
    event SecondaryBuy(address indexed msgSender, address indexed recipient, address indexed erc20zAddress, uint256 amountETHSold, uint256 num1155Purchased);

    /// @notice SecondarySell Event
    /// @param msgSender The sender of the message
    /// @param recipient The recipient of the ETH purchased
    /// @param erc20zAddress The ERC20Z address
    /// @param amountETHPurchased The amount of ETH purchased
    /// @param num1155Sold The number of 1155 tokens sold
    event SecondarySell(address indexed msgSender, address indexed recipient, address indexed erc20zAddress, uint256 amountETHPurchased, uint256 num1155Sold);

    /// @notice SecondaryComment Event
    /// @param sender The sender of the comment
    /// @param collection The collection address
    /// @param tokenId The token ID
    /// @param quantity The quantity of tokens minted
    /// @param quantity The quantity of tokens minted
    /// @param comment The comment
    /// @param secondaryType The secondary event type
    event SecondaryComment(
        address indexed sender,
        address indexed collection,
        uint256 indexed tokenId,
        uint256 quantity,
        string comment,
        SecondaryType secondaryType
    );

    /// @notice Invalid recipient
    error InvalidRecipient();

    /// @notice No ETH sent
    error NoETHSent();

    /// @notice ERC20Z minimum amount not received
    error ERC20ZMinimumAmountNotReceived();

    /// @notice ERC20Z equivalent amount not converted
    error ERC20ZEquivalentAmountNotConverted();

    /// @notice Only WETH can be received
    error OnlyWETH();

    /// @notice Operation not supported
    error NotSupported();

    /// @notice Timed Sale has not been configured for the collection and token ID
    error SaleNotSet();

    /// @notice Reverts if an address param is passed as zero address
    error AddressZero();

    /// @notice Reverts if the contract is already initialized
    error AlreadyInitialized();
}
