// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IRedeemHandler} from "./interfaces/IRedeemHandler.sol";

struct TokenConfig {
    /// @dev Price for the token to purchase.
    uint256 price;
    /// @dev Assume 0 is ETH
    address tokenAddress;
    /// @dev if set, redemptions go through this contract
    // should be an IRedeemHandler interface
    address redeemHandler;
}

struct Redemption {
    address tokenAddress;
    uint256 valueRedeemed;
}
