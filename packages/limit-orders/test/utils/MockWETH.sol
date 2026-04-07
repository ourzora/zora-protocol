// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IWETH} from "@zoralabs/coins/src/interfaces/IWETH.sol";

contract MockWETH is IWETH, ERC20 {
    constructor() ERC20("WETH", "WETH") {}

    function approve(address spender, uint256 value) public override(ERC20, IWETH) returns (bool) {
        return super.approve(spender, value);
    }

    function transfer(address to, uint256 value) public override(ERC20, IWETH) returns (bool) {
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override(ERC20, IWETH) returns (bool) {
        return super.transferFrom(from, to, value);
    }

    function balanceOf(address account) public view override(ERC20, IWETH) returns (uint256) {
        return super.balanceOf(account);
    }

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 wad) external {
        _burn(msg.sender, wad);
        (bool ok, ) = msg.sender.call{value: wad}("");
        require(ok, "WETH withdraw failed");
    }

    receive() external payable {
        _mint(msg.sender, msg.value);
    }
}
