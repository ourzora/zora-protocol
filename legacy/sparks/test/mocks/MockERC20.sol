// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(uint256 quantity) external {
        _mint(msg.sender, quantity);
    }

    uint256 private taxPercentage;

    function setTax(uint256 _taxPercentage) external {
        taxPercentage = _taxPercentage;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        uint256 tax = taxPercentage == 0 ? 0 : (value * taxPercentage) / 100;

        return super.transferFrom(from, to, value - tax);
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        uint256 tax = taxPercentage == 0 ? 0 : (value * taxPercentage) / 100;

        return super.transfer(to, value - tax);
    }
}
