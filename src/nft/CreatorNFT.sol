// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ICreatorNFT} from "./ICreatorNFT.sol";

contract CreatorNFT is ICreatorNFT {}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

contract CreatorNFT is ICreator, PublicMulticall, CreatorNFTStorageV1 {
  function constructor() {

  }
    function initialize() external {}

    modifier onlyAllowedMinter(address minter, uint256 tokenId) {
      // if (minter == LAZY_FIXED_PRICE_ADDRESS) {
      //   return true;
      // }
      // if (minter == LAZY_ALLOWLIST) {
      //   return true;
      // }
      return allowedMinters[tokenId][minter];
    }

    function mint(
      uint256 tokenId,
      uint256 maxSize,
      string uri
    ) {

    }

    function adminMint(recipient, tokenId, quantity) {

    }

    // multicall [
    //   mint() -- mint
    //   setSalesConfiguration() -- set sales configuration
    //   adminMint() -- mint reserved quantity
    // ]

    // Only allow minting one token id at time
    function purchase(
        address minter,
        uint256 tokenId,
        uint256 quantity,
        address findersRecipient,
        bytes calldata minterArguments
    ) external onlyAllowedMinter(minter, tokenId) payable returns (uint256) {
      bytes[] memory commands = IMinter(minter).requestMint(
                address(this), tokenId, quantity, findersRecipient, minterArguments
      );
      _executeCommands(commands);
    }
}
