// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IAirlock} from "../../src/interfaces/IAirlock.sol";

/// @title MockAirlock
/// @notice Mock implementation of IAirlock for testing purposes
contract MockAirlock is IAirlock {
    address private _owner;

    constructor(address owner_) {
        _owner = owner_;
    }

    function owner() external view override returns (address) {
        return _owner;
    }

    function setOwner(address newOwner) external {
        _owner = newOwner;
    }
}
