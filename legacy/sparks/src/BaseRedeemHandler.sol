// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IRedeemHandler} from "./interfaces/IRedeemHandler.sol";
import {IZoraSparks1155} from "./interfaces/IZoraSparks1155.sol";

abstract contract BaseRedeemHandler is IRedeemHandler {
    error NotZoraSparks1155();
    error AddressZero();

    IZoraSparks1155 public immutable zoraSparks1155;

    constructor(IZoraSparks1155 _zoraSparks1155) {
        if (address(_zoraSparks1155) == address(0)) {
            revert AddressZero();
        }
        zoraSparks1155 = _zoraSparks1155;
    }

    /// @dev Only the pool manager may call this function
    modifier onlySparks() {
        if (msg.sender != address(zoraSparks1155)) {
            revert NotZoraSparks1155();
        }
        _;
    }

    function handleRedeemEth(address redeemer, uint tokenId, uint quantity, address recipient) external payable virtual;

    function handleRedeemErc20(uint256 valueToRedeem, address redeemer, uint tokenId, uint quantity, address recipient) external virtual;

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IRedeemHandler).interfaceId;
    }
}
