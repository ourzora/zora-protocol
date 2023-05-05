// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IReadableAuthRegistry {
    function isAuthorized(address account) external view returns (bool);
}
