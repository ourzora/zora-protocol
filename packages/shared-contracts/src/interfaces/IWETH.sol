// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256 wad) external;

    function approve(address guy, uint256 wad) external returns (bool);

    function transfer(address dst, uint256 wad) external returns (bool);

    function transferFrom(address src, address dst, uint256 wad) external returns (bool);

    function balanceOf(address guy) external view returns (uint256);
}
