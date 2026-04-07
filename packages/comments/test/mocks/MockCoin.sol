// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {ICoinComments} from "../../src/interfaces/ICoinComments.sol";

contract MockCoin is ICoinComments, IERC165, ERC20 {
    using EnumerableSet for EnumerableSet.AddressSet;

    address internal _payoutRecipient;
    EnumerableSet.AddressSet internal _owners;

    constructor(address payoutRecipient_, address[] memory owners_) ERC20("MockCoin", "MC") {
        _payoutRecipient = payoutRecipient_;

        for (uint256 i; i < owners_.length; i++) {
            _owners.add(owners_[i]);
        }
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function balanceOf(address account) public view override(ERC20, ICoinComments) returns (uint256) {
        return super.balanceOf(account);
    }

    function payoutRecipient() public view override(ICoinComments) returns (address) {
        return _payoutRecipient;
    }

    function isOwner(address account) public view override(ICoinComments) returns (bool) {
        return _owners.contains(account);
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return type(ICoinComments).interfaceId == interfaceId;
    }
}
