// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library FixedPoint96 {
    uint8 internal constant RESOLUTION = 96;
    uint256 internal constant Q96 = 0x1000000000000000000000000;
}
