// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ICoin} from "./ICoin.sol";

interface ICoinDeployHook {
    function afterCoinDeploy(address sender, ICoin coin, bytes calldata hookData) external payable returns (bytes memory);
}
