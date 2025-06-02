// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ICoin} from "./ICoin.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {LpPosition} from "../types/LpPosition.sol";
import {PoolConfiguration} from "../types/PoolConfiguration.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

interface ICoinV4 is ICoin {
    function getPoolKey() external view returns (PoolKey memory);

    function getPoolConfiguration() external view returns (PoolConfiguration memory);

    function hooks() external view returns (IHooks);

    function initialize(
        address payoutRecipient_,
        address[] memory owners_,
        string memory tokenURI_,
        string memory name_,
        string memory symbol_,
        address platformReferrer_,
        address currency_,
        PoolKey memory poolKey_,
        uint160 sqrtPriceX96,
        PoolConfiguration memory poolConfiguration_
    ) external;
}
