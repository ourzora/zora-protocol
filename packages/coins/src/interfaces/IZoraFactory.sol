// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IZoraFactory {
    /// @notice Emitted when a coin is created
    /// @param caller The msg.sender address
    /// @param payoutRecipient The address of the creator payout recipient
    /// @param platformReferrer The address of the platform referrer
    /// @param currency The address of the currency
    /// @param uri The URI of the coin
    /// @param name The name of the coin
    /// @param symbol The symbol of the coin
    /// @param coin The address of the coin
    /// @param pool The address of the pool
    /// @param version The coin contract version
    event CoinCreated(
        address indexed caller,
        address indexed payoutRecipient,
        address indexed platformReferrer,
        address currency,
        string uri,
        string name,
        string symbol,
        address coin,
        address pool,
        string version
    );

    /// @notice Thrown when the amount of ERC20 tokens transferred does not match the expected amount
    error ERC20TransferAmountMismatch();

    /// @notice Thrown when ETH is sent with a transaction but the currency is not WETH
    error EthTransferInvalid();

    /// @notice Creates a new coin contract
    /// @param payoutRecipient The recipient of creator reward payouts; this can be updated by an owner
    /// @param owners The list of addresses that will be able to manage the coin's payout address and metadata uri
    /// @param uri The coin metadata uri
    /// @param name The name of the coin
    /// @param symbol The symbol of the coin
    /// @param platformReferrer The address to receive platform referral rewards
    /// @param currency The address of the trading currency; address(0) for ETH/WETH
    /// @param tickLower The lower tick for the Uniswap V3 LP position; ignored for ETH/WETH pairs
    /// @param orderSize The order size for the first buy; must match msg.value for ETH/WETH pairs
    function deploy(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        address platformReferrer,
        address currency,
        int24 tickLower,
        uint256 orderSize
    ) external payable returns (address, uint256);
}
