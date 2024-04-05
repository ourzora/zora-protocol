// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IRedeemHandler} from "./interfaces/IRedeemHandler.sol";
import {IZoraMints1155} from "./interfaces/IZoraMints1155.sol";

abstract contract BaseRedeemHandler is IRedeemHandler {
    error NotZoraMints1155();
    error AddressZero();

    IZoraMints1155 public immutable zoraMints1155;

    constructor(IZoraMints1155 _zoraMints1155) {
        if (address(_zoraMints1155) == address(0)) {
            revert AddressZero();
        }
        zoraMints1155 = _zoraMints1155;
    }

    /// @dev Only the pool manager may call this function
    modifier onlyMints() {
        if (msg.sender != address(zoraMints1155)) {
            revert NotZoraMints1155();
        }
        _;
    }

    function handleRedeemEth(address redeemer, uint tokenId, uint quantity, address recipient) external payable virtual;

    function handleRedeemErc20(uint256 valueToRedeem, address redeemer, uint tokenId, uint quantity, address recipient) external virtual;

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IRedeemHandler).interfaceId;
    }
}
