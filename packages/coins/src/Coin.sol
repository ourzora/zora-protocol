// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICoin, PoolConfiguration} from "./interfaces/ICoin.sol";
import {IUniswapV3Factory} from "./interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IAirlock} from "./interfaces/IAirlock.sol";
import {IProtocolRewards} from "./interfaces/IProtocolRewards.sol";
import {IWETH} from "./interfaces/IWETH.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ContractVersionBase} from "./version/ContractVersionBase.sol";
import {MultiOwnable} from "./utils/MultiOwnable.sol";
import {CoinConstants} from "./libs/CoinConstants.sol";
import {MarketConstants} from "./libs/MarketConstants.sol";
import {LpPosition} from "./types/LpPosition.sol";
import {PoolState} from "./types/PoolState.sol";
import {CoinSetupV3, UniV3Config, CoinV3Config} from "./libs/CoinSetupV3.sol";
import {UniV3BuySell, CoinConfig, SellResult} from "./libs/UniV3BuySell.sol";
import {BaseCoin} from "./BaseCoin.sol";
import {ICoinV3} from "./interfaces/ICoinV3.sol";

/*
     $$$$$$\   $$$$$$\  $$$$$$\ $$\   $$\ 
    $$  __$$\ $$  __$$\ \_$$  _|$$$\  $$ |
    $$ /  \__|$$ /  $$ |  $$ |  $$$$\ $$ |
    $$ |      $$ |  $$ |  $$ |  $$ $$\$$ |
    $$ |      $$ |  $$ |  $$ |  $$ \$$$$ |
    $$ |  $$\ $$ |  $$ |  $$ |  $$ |\$$$ |
    \$$$$$$  | $$$$$$  |$$$$$$\ $$ | \$$ |
     \______/  \______/ \______|\__|  \__|
*/
contract Coin is BaseCoin, ICoinV3 {
    using SafeERC20 for IERC20;

    address public immutable v3Factory;
    /// @notice The address of the Uniswap V3 swap router
    address public immutable swapRouter;
    /// @notice The address of the Uniswap V3 pool
    address public poolAddress;

    /// @notice The state of the market
    bytes public market;
    uint8 public marketVersion;

    /// @notice The address of the WETH contract
    address public immutable WETH;

    /// @notice deprecated
    PoolConfiguration public poolConfiguration;

    LpPosition[] public positions;

    /**
     * @notice The constructor for the static Coin contract deployment shared across all Coins.
     * @param protocolRewardRecipient_ The address of the protocol reward recipient
     * @param protocolRewards_ The address of the protocol rewards contract
     * @param weth_ The address of the WETH contract
     * @param v3Factory_ The address of the Uniswap V3 factory
     * @param swapRouter_ The address of the Uniswap V3 swap router
     * @param airlock_ The address of the Airlock contract, ownership is used for a protocol fee split.
     */
    constructor(
        address protocolRewardRecipient_,
        address protocolRewards_,
        address weth_,
        address v3Factory_,
        address swapRouter_,
        address airlock_
    ) BaseCoin(protocolRewardRecipient_, protocolRewards_, airlock_) initializer {
        if (v3Factory_ == address(0)) {
            revert AddressZero();
        }
        if (swapRouter_ == address(0)) {
            revert AddressZero();
        }
        if (airlock_ == address(0)) {
            revert AddressZero();
        }
        if (weth_ == address(0)) {
            revert AddressZero();
        }
        swapRouter = swapRouter_;
        v3Factory = v3Factory_;

        WETH = weth_;
    }

    /// @inheritdoc ICoinV3
    function initialize(
        address payoutRecipient_,
        address[] memory owners_,
        string memory tokenURI_,
        string memory name_,
        string memory symbol_,
        address platformReferrer_,
        address currency_,
        address poolAddress_,
        PoolConfiguration memory poolConfiguration_,
        LpPosition[] memory positions_
    ) public initializer {
        super._initialize(payoutRecipient_, owners_, tokenURI_, name_, symbol_, platformReferrer_);

        currency = currency_;
        poolAddress = poolAddress_;
        poolConfiguration = poolConfiguration_;
        positions = positions_;

        CoinSetupV3.deployLiquidity(positions_, poolAddress);
    }

    function buildConfig() internal view returns (CoinConfig memory coinConfig) {
        coinConfig = CoinConfig({
            protocolRewardRecipient: protocolRewardRecipient,
            platformReferrer: platformReferrer,
            payoutRecipient: payoutRecipient,
            protocolRewards: protocolRewards
        });
    }

    function getPoolConfiguration() public view returns (PoolConfiguration memory) {
        return poolConfiguration;
    }

    /// @notice Executes a buy order
    /// @param recipient The recipient address of the coins
    /// @param orderSize The amount of coins to buy
    /// @param tradeReferrer The address of the trade referrer
    /// @param sqrtPriceLimitX96 The price limit for Uniswap V3 pool swap
    function buy(
        address recipient,
        uint256 orderSize,
        uint256 minAmountOut,
        uint160 sqrtPriceLimitX96,
        address tradeReferrer
    ) public payable nonReentrant returns (uint256, uint256) {
        CoinConfig memory coinConfig = buildConfig();
        (uint256 amountOut, uint256 tradeReward, uint256 trueOrderSize) = UniV3BuySell.handleBuy(
            recipient,
            orderSize,
            minAmountOut,
            sqrtPriceLimitX96,
            tradeReferrer,
            coinConfig,
            currency,
            ISwapRouter(swapRouter),
            IWETH(WETH)
        );

        UniV3BuySell.handleMarketRewards(coinConfig, currency, poolAddress, positions, IWETH(WETH), dopplerFeeRecipient());

        emit CoinBuy(msg.sender, recipient, tradeReferrer, amountOut, currency, tradeReward, trueOrderSize);

        return (orderSize, amountOut);
    }

    /// @notice Executes a sell order
    /// @param recipient The recipient of the currency
    /// @param orderSize The amount of coins to sell
    /// @param minAmountOut The minimum amount of currency to receive
    /// @param sqrtPriceLimitX96 The price limit for the swap
    /// @param tradeReferrer The address of the trade referrer
    function sell(
        address recipient,
        uint256 orderSize,
        uint256 minAmountOut,
        uint160 sqrtPriceLimitX96,
        address tradeReferrer
    ) public nonReentrant returns (uint256, uint256) {
        // Record the coin balance of this contract before the swap
        uint256 beforeCoinBalance = balanceOf(address(this));

        // Transfer the coins from the seller to this contract
        transfer(address(this), orderSize);

        // Approve the Uniswap V3 swap router
        this.approve(swapRouter, orderSize);

        CoinConfig memory coinConfig = buildConfig();

        SellResult memory result = UniV3BuySell.handleSell(
            recipient,
            beforeCoinBalance,
            orderSize,
            minAmountOut,
            sqrtPriceLimitX96,
            tradeReferrer,
            coinConfig,
            currency,
            ISwapRouter(swapRouter),
            IWETH(WETH)
        );

        UniV3BuySell.handleMarketRewards(coinConfig, currency, poolAddress, positions, IWETH(WETH), dopplerFeeRecipient());

        emit ICoin.CoinSell(msg.sender, recipient, tradeReferrer, result.trueOrderSize, currency, result.tradeReward, result.payoutSize);

        return (result.trueOrderSize, result.payoutSize);
    }

    /// @notice Force claim any accrued secondary rewards from the market's liquidity position.
    /// @dev This function is a fallback, secondary rewards will be claimed automatically on each buy and sell.
    /// @param pushEthRewards Whether to push the ETH directly to the recipients.
    function claimSecondaryRewards(bool pushEthRewards) external nonReentrant {
        MarketRewards memory rewards = UniV3BuySell.handleMarketRewards(buildConfig(), currency, poolAddress, positions, IWETH(WETH), dopplerFeeRecipient());

        if (pushEthRewards && rewards.totalAmountCurrency > 0 && currency == WETH) {
            IProtocolRewards(protocolRewards).withdrawFor(payoutRecipient, rewards.creatorPayoutAmountCurrency);
            IProtocolRewards(protocolRewards).withdrawFor(platformReferrer, rewards.platformReferrerAmountCurrency);
            IProtocolRewards(protocolRewards).withdrawFor(protocolRewardRecipient, rewards.protocolAmountCurrency);
        }
    }

    /// @dev Called by the pool after minting liquidity to transfer the associated coins
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata) external {
        if (msg.sender != poolAddress) revert OnlyPool(msg.sender, poolAddress);

        IERC20(address(this)).safeTransfer(poolAddress, amount0Owed == 0 ? amount1Owed : amount0Owed);
    }

    /// @notice Receives ETH converted from WETH
    receive() external payable {
        require(msg.sender == WETH, OnlyWeth());
    }
}
