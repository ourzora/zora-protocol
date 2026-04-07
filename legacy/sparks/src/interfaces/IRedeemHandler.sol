// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IRedeemHandler is IERC165 {
    function handleRedeemEth(address redeemer, uint tokenId, uint quantity, address recipient) external payable;

    function handleRedeemErc20(uint256 valueToRedeem, address redeemer, uint tokenId, uint quantity, address recipient) external;
}
