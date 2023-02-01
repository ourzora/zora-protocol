// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ICreatorNFT is PublicMulticall, CreatorNFTStorageV1 {
  function constructor() {

  }
    function initialize() external {}

    modifier onlyAllowedMinter(address minter, uint256 tokenId) {
      if (minter == LAZY_FIXED_PRICE_ADDRESS) {
        return true;
      }
      if (minter == LAZY_ALLOWLIST) {
        return true;
      }
      return allowedMinters[tokenId][minter];
    }

    // Only allow minting one token id at time
    function mint(
        address minter,
        uint256 tokenId,
        uint256 quantity,
        address findersRecipient,
        bytes calldata minterArguments
    ) external onlyAllowedMinter(minter, tokenId) returns (uint256) {}
}
