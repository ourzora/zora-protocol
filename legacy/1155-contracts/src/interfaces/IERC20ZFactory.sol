// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// TODO - delete this file and import from package when published. this is just temporary for dev

interface IERC20ZFactory {
    struct ERC20Z {
        /// @notice The address of the ERC20Z
        address erc20zAddress;
        /// @notice The address of the Uniswap pool
        address poolAddress;
    }

    /// @notice ERC20Z created event
    /// @param collection The collection address
    /// @param tokenId The token ID
    /// @param erc20zAddress The ERC20Z address
    /// @param poolAddress The pool address
    /// @param name The ERC20Z name
    /// @param symbol The ERC20Z symbol
    event ERC20ZCreated(address collection, uint256 tokenId, address erc20zAddress, address poolAddress, string name, string symbol);

    /// @notice Returns the addresses of the ERC20Z and the pool for a given collection and tokenId
    /// @param collection The collection address
    /// @param tokenId The token ID
    function getAddresses(address collection, uint256 tokenId) external view returns (address tokenAddress, address poolAddress);

    /// @notice Creates a new ERC20Z and pool for a given collection and tokenId
    /// @param collection The collection address
    /// @param tokenId The token ID
    /// @param name The ERC20Z name
    /// @param symbol The ERC20Z symbol
    function createERC20Z(
        address collection,
        uint256 tokenId,
        string calldata name,
        string calldata symbol
    ) external returns (address erc20zAddress, address poolAddress);
}

interface IERC20Z {
    function activate(
        uint256 ethLiquidity,
        uint256 erc20TotalSupply,
        uint256 erc20Reserve,
        uint256 erc20Liquidity,
        uint256 erc20Excess,
        uint256 erc1155Excess
    ) external;
}
