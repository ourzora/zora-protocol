// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ICoin, PoolConfiguration} from "./interfaces/ICoin.sol";
import {ICoinComments} from "./interfaces/ICoinComments.sol";
import {IERC7572} from "./interfaces/IERC7572.sol";
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
import {FullMath} from "./utils/uniswap/FullMath.sol";
import {TickMath} from "./utils/uniswap/TickMath.sol";
import {LiquidityAmounts} from "./utils/uniswap/LiquidityAmounts.sol";
import {CoinConstants} from "./libs/CoinConstants.sol";
import {MarketConstants} from "./libs/MarketConstants.sol";
import {LpPosition} from "./types/LpPosition.sol";
import {PoolState} from "./types/PoolState.sol";
import {CoinSetupV3, UniV3Config, CoinV3Config} from "./libs/CoinSetupV3.sol";
import {UniV3BuySell, CoinConfig} from "./libs/UniV3BuySell.sol";

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
contract Coin is ICoin, ContractVersionBase, ERC20PermitUpgradeable, MultiOwnable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice The address of the WETH contract
    address public immutable WETH;
    /// @notice The address of the Uniswap V3 factory
    address public immutable v3Factory;
    /// @notice The address of the Uniswap V3 swap router
    address public immutable swapRouter;
    /// @notice The address of the Airlock contract, ownership is used for a protocol fee split.
    address public immutable airlock;
    /// @notice The address of the protocol rewards contract
    address public immutable protocolRewards;
    /// @notice The address of the protocol reward recipient
    address public immutable protocolRewardRecipient;

    /// @notice The metadata URI
    string public tokenURI;
    /// @notice The address of the coin creator
    address public payoutRecipient;
    /// @notice The address of the platform referrer
    address public platformReferrer;
    /// @notice The address of the Uniswap V3 pool
    address public poolAddress;
    /// @notice The address of the currency
    address public currency;

    /// @notice The state of the market
    bytes public market;
    uint8 public marketVersion;

    /// @notice deprecated
    PoolConfiguration public poolConfiguration;

    /// @notice Returns the state of the pool
    /// @dev This is a legacy function for compatibility with doppler default state
    /// @return asset The address of the asset
    /// @return numeraire The address of the numeraire
    /// @return tickLower The lower tick
    /// @return tickUpper The upper tick
    /// @return numPositions The number of discovery positions
    /// @return isInitialized Whether the pool is initialized
    /// @return isExited Whether the pool is exited
    /// @return maxShareToBeSold The maximum share to be sold
    /// @return totalTokensOnBondingCurve The total tokens on the bonding curve
    function poolState()
        external
        view
        returns (
            address asset,
            address numeraire,
            int24 tickLower,
            int24 tickUpper,
            uint16 numPositions,
            bool isInitialized,
            bool isExited,
            uint256 maxShareToBeSold,
            uint256 totalTokensOnBondingCurve
        )
    {
        asset = address(this);
        numeraire = currency;
        tickLower = poolConfiguration.tickLower;
        tickUpper = poolConfiguration.tickUpper;
        numPositions = poolConfiguration.numPositions;
        isInitialized = true;
        isExited = false;
        maxShareToBeSold = poolConfiguration.maxDiscoverySupplyShare;
        totalTokensOnBondingCurve = CoinConstants.POOL_LAUNCH_SUPPLY;
    }

    /**
     * @notice The constructor for the static Coin contract deployment shared across all Coins.
     * @param _protocolRewardRecipient The address of the protocol reward recipient
     * @param _protocolRewards The address of the protocol rewards contract
     * @param _weth The address of the WETH contract
     * @param _v3Factory The address of the Uniswap V3 factory
     * @param _swapRouter The address of the Uniswap V3 swap router
     * @param _airlock The address of the Airlock contract, ownership is used for a protocol fee split.
     */
    constructor(
        address _protocolRewardRecipient,
        address _protocolRewards,
        address _weth,
        address _v3Factory,
        address _swapRouter,
        address _airlock
    ) initializer {
        if (_protocolRewardRecipient == address(0)) {
            revert AddressZero();
        }
        if (_protocolRewards == address(0)) {
            revert AddressZero();
        }
        if (_weth == address(0)) {
            revert AddressZero();
        }
        if (_v3Factory == address(0)) {
            revert AddressZero();
        }
        if (_swapRouter == address(0)) {
            revert AddressZero();
        }
        if (_airlock == address(0)) {
            revert AddressZero();
        }

        protocolRewardRecipient = _protocolRewardRecipient;
        protocolRewards = _protocolRewards;
        WETH = _weth;
        swapRouter = _swapRouter;
        v3Factory = _v3Factory;
        airlock = _airlock;
    }

    /// @notice Initializes a new coin
    /// @param payoutRecipient_ The address of the coin creator
    /// @param tokenURI_ The metadata URI
    /// @param name_ The coin name
    /// @param symbol_ The coin symbol
    /// @param poolConfig_ The parameters for the v3 pool and liquidity
    /// @param platformReferrer_ The address of the platform referrer
    function initialize(
        address payoutRecipient_,
        address[] memory owners_,
        string memory tokenURI_,
        string memory name_,
        string memory symbol_,
        bytes memory poolConfig_,
        address platformReferrer_
    ) public initializer {
        // Validate the creation parameters
        if (payoutRecipient_ == address(0)) {
            revert AddressZero();
        }

        // Set base contract state
        __ERC20_init(name_, symbol_);
        __ERC20Permit_init(name_);
        __MultiOwnable_init(owners_);
        __ReentrancyGuard_init();

        // Set mutable state
        _setPayoutRecipient(payoutRecipient_);
        _setContractURI(tokenURI_);

        // Store the referrer if set
        platformReferrer = platformReferrer_ == address(0) ? protocolRewardRecipient : platformReferrer_;

        // Mint the total supply
        _mint(address(this), CoinConstants.MAX_TOTAL_SUPPLY);

        // Distribute the creator launch reward
        _transfer(address(this), payoutRecipient, CoinConstants.CREATOR_LAUNCH_REWARD);

        UniV3Config memory uniswapV3Config = UniV3Config({weth: WETH, v3Factory: v3Factory, swapRouter: swapRouter, airlock: airlock});

        // Deploy the pool
        (currency, poolAddress, poolConfiguration) = CoinSetupV3.setupPool(poolConfig_, uniswapV3Config, address(this));

        // Split out the deployment of liquidity to avoid stack too deep
        CoinSetupV3.deployLiquidity(address(this), currency, poolConfiguration, poolAddress);
    }

    function buildCoinConfig() internal view returns (CoinConfig memory coinConfig) {
        coinConfig = CoinConfig({
            protocolRewardRecipient: protocolRewardRecipient,
            platformReferrer: platformReferrer,
            currency: currency,
            payoutRecipient: payoutRecipient,
            protocolRewards: protocolRewards,
            poolConfiguration: poolConfiguration,
            poolAddress: poolAddress,
            uniswapV3Config: UniV3Config({weth: WETH, v3Factory: v3Factory, swapRouter: swapRouter, airlock: airlock})
        });
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
        return UniV3BuySell.buy(recipient, orderSize, minAmountOut, sqrtPriceLimitX96, tradeReferrer, address(this), buildCoinConfig());
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

        return UniV3BuySell.sell(recipient, beforeCoinBalance, orderSize, minAmountOut, sqrtPriceLimitX96, tradeReferrer, buildCoinConfig());
    }

    /// @notice Enables a user to burn their tokens
    /// @param amount The amount of tokens to burn
    function burn(uint256 amount) external {
        // This burn function sets the from as msg.sender, so having an unauthed call is safe.
        _burn(msg.sender, amount);
    }

    /// @notice Force claim any accrued secondary rewards from the market's liquidity position.
    /// @dev This function is a fallback, secondary rewards will be claimed automatically on each buy and sell.
    /// @param pushEthRewards Whether to push the ETH directly to the recipients.
    function claimSecondaryRewards(bool pushEthRewards) external nonReentrant {
        MarketRewards memory rewards = UniV3BuySell.handleMarketRewards(address(this), buildCoinConfig());

        if (pushEthRewards && rewards.totalAmountCurrency > 0 && currency == WETH) {
            IProtocolRewards(protocolRewards).withdrawFor(payoutRecipient, rewards.creatorPayoutAmountCurrency);
            IProtocolRewards(protocolRewards).withdrawFor(platformReferrer, rewards.platformReferrerAmountCurrency);
            IProtocolRewards(protocolRewards).withdrawFor(protocolRewardRecipient, rewards.protocolAmountCurrency);
        }
    }

    /// @notice Set the creator's payout address
    /// @param newPayoutRecipient The new recipient address
    function setPayoutRecipient(address newPayoutRecipient) external onlyOwner {
        _setPayoutRecipient(newPayoutRecipient);
    }

    /// @notice Set the contract URI
    /// @param newURI The new URI
    function setContractURI(string memory newURI) external onlyOwner {
        _setContractURI(newURI);
    }

    /// @notice The contract metadata
    function contractURI() external view returns (string memory) {
        return tokenURI;
    }

    /// @notice ERC165 interface support
    /// @param interfaceId The interface ID to check
    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        return
            interfaceId == type(ICoin).interfaceId ||
            interfaceId == type(ICoinComments).interfaceId ||
            interfaceId == type(IERC7572).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    /// @notice Receives ETH converted from WETH
    receive() external payable {
        require(msg.sender == WETH, OnlyWeth());
    }

    /// @dev Called by the pool after minting liquidity to transfer the associated coins
    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata) external {
        if (msg.sender != poolAddress) revert OnlyPool(msg.sender, poolAddress);

        IERC20(address(this)).safeTransfer(poolAddress, amount0Owed == 0 ? amount1Owed : amount0Owed);
    }

    /// @dev Overrides ERC20's _update function to emit a superset `CoinTransfer` event
    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);

        emit CoinTransfer(from, to, value, balanceOf(from), balanceOf(to));
    }

    /// @dev Used to set the payout recipient on coin creation and updates
    /// @param newPayoutRecipient The new recipient address
    function _setPayoutRecipient(address newPayoutRecipient) internal {
        if (newPayoutRecipient == address(0)) {
            revert AddressZero();
        }

        emit CoinPayoutRecipientUpdated(msg.sender, payoutRecipient, newPayoutRecipient);

        payoutRecipient = newPayoutRecipient;
    }

    /// @dev Used to set the contract URI on coin creation and updates
    /// @param newURI The new URI
    function _setContractURI(string memory newURI) internal {
        emit ContractMetadataUpdated(msg.sender, newURI, name());
        emit ContractURIUpdated();

        tokenURI = newURI;
    }
}
