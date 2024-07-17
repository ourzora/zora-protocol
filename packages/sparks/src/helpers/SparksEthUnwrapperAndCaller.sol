// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IZoraSparks1155} from "../interfaces/IZoraSparks1155.sol";
import {IZoraSparks1155Managed} from "../interfaces/IZoraSparks1155Managed.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Redemption} from "../ZoraSparksTypes.sol";
import {IUnwrapAndForwardAction} from "../interfaces/IUnwrapAndForwardAction.sol";

/// @title Unwraps eth value of SPARKS and sends the eth value to a receiver with a call, refunding any remaining eth to
/// the original owner of the SPARKs.  Works when SPARKS backed by ETH are transferred to this contract.  ERC20 based SPARKs
/// are not supported.
/// @author oveddan
contract SparksEthUnwrapperAndCaller {
    bytes4 constant ON_ERC1155_BATCH_RECEIVED_HASH = IERC1155Receiver.onERC1155BatchReceived.selector;
    bytes4 constant ON_ERC1155_RECEIVED_HASH = IERC1155Receiver.onERC1155Received.selector;

    IZoraSparks1155 private immutable zoraSparks1155;
    bool private expectReceive;

    error NotZoraSparks1155();
    error NotExpectingReceive();
    error ERC20NotSupported(uint256 tokenId);
    error TransferFailed(bytes data);
    error UnknownUserAction();
    error CallFailed(bytes data);

    constructor(IZoraSparks1155 _zoraSparks1155) {
        zoraSparks1155 = _zoraSparks1155;
    }

    /// @dev Only the pool manager may call this function
    modifier onlySparks() {
        if (msg.sender != address(zoraSparks1155)) {
            revert NotZoraSparks1155();
        }

        _;
    }

    function permitWithAdditionalValue(IZoraSparks1155Managed.PermitBatch calldata permit, bytes calldata signature) external payable {
        IZoraSparks1155Managed(address(zoraSparks1155)).permitSafeTransferBatch(permit, signature);
    }

    function onERC1155Received(address, address from, uint256 id, uint256 value, bytes calldata data) external onlySparks returns (bytes4) {
        // temporarily enable receiving eth
        expectReceive = true;
        // redeem the SPARKs - all eth will be sent to this contract
        Redemption memory redemption = zoraSparks1155.redeem(id, value, address(this));
        // disable receiving ETH
        expectReceive = false;

        // if any redemption is erc20, revert
        if (redemption.tokenAddress != address(0)) {
            revert ERC20NotSupported(0);
        }

        // forward eth balance redeemed to the desired receiver, calling it with the data and desired
        // value to forward.
        // refund the remaining eth to the original owner of the SPARKs
        _sendToReceiverAndRefundExcess(data, from);

        return ON_ERC1155_RECEIVED_HASH;
    }

    function onERC1155BatchReceived(
        address,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external onlySparks returns (bytes4) {
        // temporarily enable receiving eth
        expectReceive = true;
        // redeem the SPARKs - all eth will be sent to this contract
        Redemption[] memory redemptions = zoraSparks1155.redeemBatch(ids, values, address(this));

        expectReceive = false;

        // if any redemption is erc20, revert
        for (uint256 i = 0; i < redemptions.length; i++) {
            if (redemptions[i].tokenAddress != address(0)) {
                revert ERC20NotSupported(ids[i]);
            }
        }

        // forward eth balance redeemed to the desired receiver, calling it with the data and desired
        // value to forward.
        _sendToReceiverAndRefundExcess(data, from);

        return ON_ERC1155_BATCH_RECEIVED_HASH;
    }

    function _sendToReceiverAndRefundExcess(bytes calldata data, address refundRecipient) internal {
        bytes4 action = bytes4(data[:4]);

        if (action != IUnwrapAndForwardAction.callWithEth.selector) {
            revert UnknownUserAction();
        }

        // decode the call: get address to forward eth to, encoded function to call on it, and value to forward
        (address receiverAddress, bytes memory call, uint256 valueToSend) = abi.decode(data[4:], (address, bytes, uint256));

        (bool success, bytes memory callResponseData) = receiverAddress.call{value: valueToSend}(call);
        if (!success) {
            revert CallFailed(callResponseData);
        }

        // if theres any remaining eth, refund it to the original owner of the SPARKs
        if (address(this).balance > 0) {
            Address.sendValue(payable(refundRecipient), address(this).balance);
        }
    }

    receive() external payable {
        if (!expectReceive) {
            revert NotExpectingReceive();
        }
    }
}
