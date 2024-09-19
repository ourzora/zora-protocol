// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract EchoerContract {
    function balance(uint256 _value) external {}
    function call(address target, uint256 value, bytes memory data) external {}
}

/**
 * @author iainnash
 * @notice This shim contract allows for better error reporting and catches for smart wallet multi-execution
 * This shim contract replaces the Coinbase wallet simulator and more explicitly throws errors with additional information and context around operations failing.
 * This is used for simulating execution success along with better error reporting and debugging for our users.
 */
contract ExecuteBatchSimulator {
    /// @notice Call has failed to execute.
    error CallExecuteFailure(address target, uint256 value, bytes data, bytes errorMessage);
    /// @notice Call does not have enough value.
    error CallHasNotEnoughValue(address target, uint256 value, bytes data, uint256 balance);
    /// @notice Call target has no code but data is being sent. 99% of the time this is incorrect.
    error CallExecuteTargetNoCodeButData(address target, uint256 value, bytes data);
    /// @notice Function call does not match any public selectors in this contract.
    error InvalidFunctionCall(uint256 value);

    EchoerContract echoer;

    /// @notice Represents a call to make.
    struct Call {
        /// @dev The address to call.
        address target;
        /// @dev The value to send when making the call.
        uint256 value;
        /// @dev The data of the call.
        bytes data;
    }

    event ReceivedEth(address sender, uint256 value);
    event CallOp(address target, uint256 value, bytes data);

    /// @notice Shims coinbase wallet's executeBatch function
    /// @param calls calls to execute
    function executeBatch(Call[] calldata calls) external payable {
        echoer = new EchoerContract();
        for (uint256 i = 0; i < calls.length; i++) {
            echoer.call(calls[i].target, calls[i].value, calls[i].data);
        }
        for (uint256 i = 0; i < calls.length; i++) {
            echoer.balance(address(this).balance);
            _call(calls[i].target, calls[i].value, calls[i].data);
        }
    }

    /// @notice Shims coinbase wallet's execute function
    /// @param target target to execute
    /// @param value value to use to execute
    /// @param data calldata to execute
    function execute(address target, uint256 value, bytes calldata data) external payable {
        echoer = new EchoerContract();
        echoer.balance(address(this).balance);
        _call(target, value, data);
    }

    /// @notice Internal underlying call function
    function _call(address target, uint256 value, bytes memory data) public {
        emit CallOp(target, value, data);
        echoer.call(target, value, data);

        uint256 balance = address(this).balance;
        if (balance < value) {
            revert CallHasNotEnoughValue(target, value, data, balance);
        }

        if (target.code.length == 0 && data.length > 0) {
            revert CallExecuteTargetNoCodeButData(target, value, data);
        }

        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            revert CallExecuteFailure(target, value, data, result);
        }
    }

    /// @notice Function handling for unknown calls to help more clearly debug
    fallback() external payable {
        revert InvalidFunctionCall(0);
    }

    /// @notice Function handling for unknown calls to help more clearly debug
    receive() external payable {
        emit ReceivedEth(msg.sender, msg.value);
    }
}
