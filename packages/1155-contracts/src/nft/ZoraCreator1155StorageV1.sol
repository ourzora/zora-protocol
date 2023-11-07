// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IZoraCreator1155TypesV1, ITransferHookReceiver} from "./IZoraCreator1155TypesV1.sol";

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

/// Imagine. Mint. Enjoy.
/// @notice Storage for 1155 contract
/// @author @iainnash / @tbtstl
abstract contract ZoraCreator1155StorageV1 is IZoraCreator1155TypesV1 {

  struct ZoraCreator1155StorageV1Data {
    /// @notice token data stored for each token
    mapping(uint256 => TokenData) tokens;
    /// @notice metadata renderer contract for each token
    mapping(uint256 => address) metadataRendererContract;

    /// @notice next token id available when using a linear mint style (default for launch)
    uint256 nextTokenId;
    /// @notice Global contract configuration
    ContractConfig config;
  }

  function tokens(uint256 tokenId) public view returns (TokenData memory) {
    return _get1155Storage().tokens[tokenId];
  }

  function metadataRendererContract(uint256 tokenId) public view returns (address) {
    return _get1155Storage().metadataRendererContract[tokenId];
  }

  function nextTokenId() public view returns (uint256) {
    return _get1155Storage().nextTokenId;
  }

  function config() public view returns (address owner,
        uint96 __gap1,
        address payable fundsRecipient,
        uint96 __gap2,
        ITransferHookReceiver transferHook,
        uint96 __gap3)
      {
    ContractConfig storage configLocal = _get1155Storage().config;
    owner = configLocal.owner;
    __gap1 = configLocal.__gap1;
    fundsRecipient = configLocal.fundsRecipient;
    __gap2 = configLocal.__gap2;
    transferHook = configLocal.transferHook;
    __gap3 = configLocal.__gap3;
  }

  function _get1155Storage() internal pure returns (ZoraCreator1155StorageV1Data storage $) {
    assembly {
      $.slot := 454
    }
  }
}
