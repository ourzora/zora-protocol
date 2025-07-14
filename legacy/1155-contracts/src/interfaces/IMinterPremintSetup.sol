// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/// Used on Minters to support setting the sales config for a premint based token config
interface IMinterPremintSetup {
    /// Sets the sales config for ta token based on the premint sales config, which's values
    /// are to be decoded by the corresponding minter.
    function setPremintSale(uint256 tokenId, bytes calldata premintSalesConfig) external;
}
