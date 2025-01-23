// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

interface IZoraFactory {
    /// @notice Emitted when a new Wow token is created
    /// @param factoryAddress The address of the factory that created the token
    /// @param creator The address of the creator of the token
    /// @param platformReferrer The address of the platform referrer
    /// @param protocolRewardRecipient The address of the protocol fee recipient
    /// @param bondingCurve The address of the bonding curve
    /// @param tokenURI The URI of the token
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param tokenAddress The address of the token
    /// @param poolAddress The address of the pool
    event WowTokenCreated(
        address indexed factoryAddress,
        address indexed creator,
        address platformReferrer,
        address protocolRewardRecipient,
        address bondingCurve,
        string tokenURI,
        string name,
        string symbol,
        address tokenAddress,
        address poolAddress
    );

    /// @notice Emitted when a coin is created
    /// @param deployer The msg.sender address of coin creation
    /// @param creator The address of the creator of the coin
    /// @param payoutRecipient The address of the creator payout recipient
    /// @param platformReferrer The address of the platform referrer
    /// @param currency The address of the currency
    /// @param tokenURI The URI of the coin
    /// @param name The name of the coin
    /// @param symbol The symbol of the coin
    /// @param coin The address of the coin
    /// @param pool The address of the pool
    event CoinCreated(
        address indexed deployer,
        address indexed creator, // TODO remove after backend approval
        address indexed payoutRecipient,
        address platformReferrer,
        address currency,
        string tokenURI,
        string name,
        string symbol,
        address coin,
        address pool
    );

    /// @notice Thrown when the amount of ERC20 tokens transferred does not match the expected amount
    error ERC20TransferAmountMismatch();

    /// @notice Thrown when ETH is sent with a transaction but the currency is not WETH
    error EthTransferInvalid();

    /// @notice Deploys a coin
    /// @param _creator The address of the token creator
    /// @param _platformReferrer The address of the platform referrer
    /// @param _tokenURI The ERC20z token URI
    /// @param _name The ERC20 token name
    /// @param _symbol The ERC20 token symbol
    function deploy(
        address _creator,
        address _platformReferrer,
        string memory _tokenURI,
        string memory _name,
        string memory _symbol
    ) external payable returns (address);
}
