// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ICoin} from "../../interfaces/ICoin.sol";
import {IZoraFactory} from "../../interfaces/IZoraFactory.sol";
import {ICoinDeployHook} from "../../interfaces/ICoinDeployHook.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title Immutable State
/// @notice A collection of immutable state variables, commonly used across multiple contracts
contract ImmutableState {
    IZoraFactory public immutable factory;

    /// @notice Thrown when the caller is not Factory
    error NotFactory();

    /// @notice Thrown when a zero address is used
    error AddressZero();

    /// @notice Only allow calls from the PoolManager contract
    modifier onlyFactory() {
        require(msg.sender == address(factory), NotFactory());
        _;
    }

    constructor(IZoraFactory _factory) {
        require(address(_factory) != address(0), AddressZero());
        factory = _factory;
    }
}

interface IHasAfterCoinDeploy {
    /// @notice Hook that is called after a coin is deployed
    /// @param sender The address that called the factory
    /// @param coin The coin that was deployed
    /// @param hookData The data passed to the hook
    /// @return hookDataOut The data returned by the hook
    /// @dev This function can only be called by the factory
    function afterCoinDeploy(address sender, ICoin coin, bytes calldata hookData) external payable returns (bytes memory);
}

/// @title Base Hook
/// @notice abstract contract for coin deploy hook implementations
abstract contract BaseCoinDeployHook is ImmutableState, IHasAfterCoinDeploy, IERC165 {
    /// @notice Thrown when a hook method is not implemented
    error HookNotImplemented();

    constructor(IZoraFactory _factory) ImmutableState(_factory) {}

    /// @inheritdoc IHasAfterCoinDeploy
    function afterCoinDeploy(address sender, ICoin coin, bytes calldata hookData) external payable onlyFactory returns (bytes memory) {
        return _afterCoinDeploy(sender, coin, hookData);
    }

    function _afterCoinDeploy(address, ICoin, bytes calldata) internal virtual returns (bytes memory) {
        revert HookNotImplemented();
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IHasAfterCoinDeploy).interfaceId;
    }
}
