// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

abstract contract ERC20ZStorageDataLocation {
    /// @notice Storage for the ERC20Z contract
    struct ERC20ZStorage {
        /// @notice The collection address
        address collection;
        /// @notice The token ID
        uint256 tokenId;
        /// @notice The pool address
        address pool;
        /// @notice The sale strategy address
        address saleStrategy;
        /// @notice Initial liquidity token ID
        uint256 initialLiquidityPoolPositionId;
    }

    /// @dev keccak256(abi.encode(uint256(keccak256("zora.storage.ERC20Z")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant ERC20ZStorageLocation = 0xeefd27cc0d91b24ef31e7ac9cedd39e394575798761a28c0ac33d509617d9d00;

    /// @notice get ERC20ZStorage
    function _getERC20ZStorage() internal pure returns (ERC20ZStorage storage erc20zStorage) {
        assembly {
            erc20zStorage.slot := ERC20ZStorageLocation
        }
    }
}
