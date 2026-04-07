// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IUniswapV3Pool} from "@zoralabs/shared-contracts/interfaces/uniswap/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICointag} from "../interfaces/ICointag.sol";

abstract contract CointagStorage {
    // keccak256(abi.encode(uint256(keccak256("cointag.storage.CointagStorage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant COINTAG_STORAGE_LOCATION = 0x25167c63cb0f1e2a2dd36e690b0f8b529147dfbc8466d2e95c11b78d76fec200;

    function _getCointagStorageV1() internal pure returns (ICointag.CointagStorageV1 storage $) {
        assembly {
            $.slot := COINTAG_STORAGE_LOCATION
        }
    }
}
