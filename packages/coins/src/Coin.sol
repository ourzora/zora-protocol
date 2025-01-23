// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {CoinConstants} from "./utils/CoinConstants.sol";
import {MultiOwnable} from "./utils/MultiOwnable.sol";
import {TickMath} from "./utils/TickMath.sol";
import {ICoin} from "./interfaces/ICoin.sol";
import {ICoinComments} from "./interfaces/ICoinComments.sol";
import {IERC7572} from "./interfaces/IERC7572.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IProtocolRewards} from "./interfaces/IProtocolRewards.sol";
import {IWETH} from "./interfaces/IWETH.sol";

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
contract Coin is ICoin, IERC165, IERC721Receiver, IERC7572, CoinConstants, ERC20Upgradeable, MultiOwnable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    address public immutable WETH;
    address public immutable nonfungiblePositionManager;
    address public immutable swapRouter;
    address public immutable protocolRewards;
    address public immutable protocolRewardRecipient;

    address public payoutRecipient;
    address public platformReferrer;
    address public poolAddress;
    address public currency;
    uint256 public lpTokenId;
    string public tokenURI;

    constructor(
        address _protocolRewardRecipient,
        address _protocolRewards,
        address _weth,
        address _nonfungiblePositionManager,
        address _swapRouter
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
        if (_nonfungiblePositionManager == address(0)) {
            revert AddressZero();
        }
        if (_swapRouter == address(0)) {
            revert AddressZero();
        }

        protocolRewardRecipient = _protocolRewardRecipient;
        protocolRewards = _protocolRewards;
        WETH = _weth;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        swapRouter = _swapRouter;
    }

    /// @notice Initializes a new coin
    /// @param payoutRecipient_ The address of the coin creator
    /// @param tokenURI_ The metadata URI
    /// @param name_ The coin name
    /// @param symbol_ The coin symbol
    /// @param platformReferrer_ The address of the platform referrer
    /// @param currency_ The address of the currency
    /// @param tickLower_ The tick lower for the Uniswap V3 pool; ignored for ETH/WETH
    function initialize(
        address payoutRecipient_,
        address[] memory owners_,
        string memory tokenURI_,
        string memory name_,
        string memory symbol_,
        address platformReferrer_,
        address currency_,
        int24 tickLower_
    ) public initializer {
        // Validate the creation parameters
        if (payoutRecipient_ == address(0)) {
            revert AddressZero();
        }

        // Set base contract state
        __ERC20_init(name_, symbol_);
        __MultiOwnable_init(owners_);
        __ReentrancyGuard_init();

        // Set mutable state
        _setPayoutRecipient(payoutRecipient_);
        _setContractURI(tokenURI_);

        // Set immutable state
        platformReferrer = platformReferrer_ == address(0) ? protocolRewardRecipient : platformReferrer_;
        currency = currency_ == address(0) ? WETH : currency_;

        // Mint the total supply
        _mint(address(this), MAX_TOTAL_SUPPLY);

        // Distribute launch rewards
        _transfer(address(this), payoutRecipient, CREATOR_LAUNCH_REWARD);
        _transfer(address(this), platformReferrer, PLATFORM_REFERRER_LAUNCH_REWARD);
        _transfer(address(this), protocolRewardRecipient, PROTOCOL_LAUNCH_REWARD);

        // Approve the transfer of the remaining supply to the pool
        IERC20(address(this)).safeIncreaseAllowance(address(nonfungiblePositionManager), POOL_LAUNCH_SUPPLY);

        // Deploy the pool
        _deployPool(tickLower_);
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
    ) public payable nonReentrant returns (uint256) {
        // Ensure the recipient is not the zero address
        if (recipient == address(0)) {
            revert AddressZero();
        }

        // Calculate the trade reward
        uint256 tradeReward = _calculateReward(orderSize, TOTAL_FEE_BPS);

        // Calculate the remaining size
        uint256 trueOrderSize = orderSize - tradeReward;

        // Handle incoming currency
        _handleIncomingCurrency(orderSize, trueOrderSize);

        // Set up the swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: currency,
            tokenOut: address(this),
            fee: LP_FEE,
            recipient: recipient,
            amountIn: trueOrderSize,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        // Execute the swap
        uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(params);

        _handleTradeRewards(tradeReward, tradeReferrer);

        _handleMarketRewards();

        emit WowTokenBuy(
            msg.sender,
            recipient,
            tradeReferrer,
            msg.value,
            tradeReward,
            trueOrderSize,
            amountOut,
            balanceOf(recipient),
            "",
            totalSupply(),
            marketType()
        );

        emit CoinBuy(msg.sender, recipient, tradeReferrer, amountOut, currency, tradeReward, trueOrderSize, "");

        return amountOut;
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
    ) public nonReentrant returns (uint256) {
        // Ensure the recipient is not the zero address
        if (recipient == address(0)) {
            revert AddressZero();
        }

        // Transfer the coins from the seller to this contract
        transfer(address(this), orderSize);

        // Approve the Uniswap V3 swap router
        this.approve(swapRouter, orderSize);

        // Set the swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(this),
            tokenOut: currency,
            fee: LP_FEE,
            recipient: address(this),
            amountIn: orderSize,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        // Execute the swap
        uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(params);

        // If currency is WETH, convert to ETH
        if (currency == WETH) {
            IWETH(WETH).withdraw(amountOut);
        }

        // Calculate the trade reward
        uint256 tradeReward = _calculateReward(amountOut, TOTAL_FEE_BPS);

        // Calculate the payout after the fee
        uint256 payoutSize = amountOut - tradeReward;

        _handleSellPayout(payoutSize, recipient);

        _handleTradeRewards(tradeReward, tradeReferrer);

        _handleMarketRewards();

        emit WowTokenSell(
            msg.sender,
            recipient,
            tradeReferrer,
            amountOut,
            tradeReward,
            payoutSize,
            orderSize,
            balanceOf(recipient),
            "",
            totalSupply(),
            marketType()
        );

        emit CoinSell(msg.sender, recipient, tradeReferrer, orderSize, currency, tradeReward, payoutSize, "");

        return amountOut;
    }

    /// @notice DEPRECATED: For backwards compatibility with buy orders on legacy Wow coins
    /// @param recipient The recipient address of the coins
    /// @param tradeReferrer The address of the trade referrer
    /// @param minOrderSize The minimum coins to prevent slippage
    /// @param sqrtPriceLimitX96 The price limit for Uniswap V3 pool swap
    function buy(
        address recipient,
        address /* refundRecipient - deprecated */,
        address tradeReferrer,
        string memory /* comment - deprecated */,
        MarketType /* expectedMarketType - deprecated */,
        uint256 minOrderSize,
        uint160 sqrtPriceLimitX96
    ) public payable returns (uint256) {
        return buy(recipient, msg.value, minOrderSize, sqrtPriceLimitX96, tradeReferrer);
    }

    /// @notice DEPRECATED: For backwards compatibility with sell orders on legacy Wow coins
    /// @param amount The number of coins to sell
    /// @param recipient The address to receive the ETH
    /// @param tradeReferrer The address of the trade referrer
    /// @param minPayoutSize The minimum ETH payout to prevent slippage
    /// @param sqrtPriceLimitX96 The price limit for Uniswap V3 pool swap
    function sell(
        uint256 amount,
        address recipient,
        address tradeReferrer,
        string memory /* comment - deprecated */,
        MarketType /* expectedMarketType - deprecated */,
        uint256 minPayoutSize,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256) {
        return sell(recipient, amount, minPayoutSize, sqrtPriceLimitX96, tradeReferrer);
    }

    /// @notice Enables a user to burn their tokens
    /// @param amount The amount of tokens to burn
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    /// @notice Force claim any accrued secondary rewards from the market's liquidity position.
    /// @dev This function is a fallback, secondary rewards will be claimed automatically on each buy and sell.
    /// @param pushEthRewards Whether to push the ETH directly to the recipients.
    function claimSecondaryRewards(bool pushEthRewards) external {
        MarketRewards memory rewards = _handleMarketRewards();

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

    /// @notice The contract version
    function contractVersion() external pure returns (string memory) {
        return "1.0.0";
    }

    /// @notice DEPRECATED: For backwards compatibility with legacy Wow coins
    /// @dev The creator's payout address
    function tokenCreator() public view returns (address) {
        return payoutRecipient;
    }

    /// @notice DEPRECATED: For backwards compatibility with legacy Wow coins
    /// @dev The market type
    function marketType() public pure returns (MarketType) {
        return MarketType.UNISWAP_POOL;
    }

    /// @notice DEPRECATED: For backwards compatibility with legacy Wow coins
    /// @dev The current coin market state and address
    function state() external view returns (MarketState memory) {
        return MarketState({marketType: marketType(), marketAddress: poolAddress});
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

    /// @notice Receives ETH and executes a buy order.
    receive() external payable {
        if (msg.sender == WETH) {
            return;
        }

        buy(msg.sender, msg.value, 0, 0, address(0));
    }

    /// @dev For receiving the Uniswap V3 LP NFT on market graduation.
    function onERC721Received(address, address, uint256, bytes calldata) external view returns (bytes4) {
        if (msg.sender != poolAddress) revert OnlyPool();

        return this.onERC721Received.selector;
    }

    /// @dev No-op to allow a swap on the pool to set the correct initial price, if needed
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {}

    /// @dev Overrides ERC20's _update function to
    ///      - Prevent transfers to the pool if the market has not graduated.
    ///      - Emit the superset `WowTokenTransfer` event with each ERC20 transfer.
    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);

        emit WowTokenTransfer(from, to, value, balanceOf(from), balanceOf(to), totalSupply());

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

    /// @dev Deploy the pool
    function _deployPool(int24 tickLower_) internal {
        // If WETH is passed or set as the currency, set the default lower tick
        if (currency == WETH) {
            tickLower_ = LP_TICK_LOWER;
        }

        // Note: This validation happens on the Uniswap pool already; reverting early here for clarity
        // If currency is not WETH: ensure lower tick is less than upper tick and satisfies the 200 tick spacing requirement for 1% Uniswap V3 pools
        if (currency != WETH && (tickLower_ >= LP_TICK_UPPER || tickLower_ % 200 != 0)) {
            revert InvalidCurrencyLowerTick();
        }

        // Sort the token addresses
        address token0 = address(this) < currency ? address(this) : currency;
        address token1 = address(this) < currency ? currency : address(this);

        // If the coin is token0
        bool isCoinToken0 = token0 == address(this);

        // Determine the tick values
        int24 tickLower = isCoinToken0 ? tickLower_ : -LP_TICK_UPPER;
        int24 tickUpper = isCoinToken0 ? LP_TICK_UPPER : -tickLower_;

        // Calculate the starting price for the pool
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(isCoinToken0 ? tickLower : tickUpper);

        // Determine the initial liquidity amounts
        uint256 amount0 = isCoinToken0 ? POOL_LAUNCH_SUPPLY : 0;
        uint256 amount1 = isCoinToken0 ? 0 : POOL_LAUNCH_SUPPLY;

        // Create and initialize the pool
        poolAddress = INonfungiblePositionManager(nonfungiblePositionManager).createAndInitializePoolIfNecessary(token0, token1, LP_FEE, sqrtPriceX96);

        // Construct the LP data
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: LP_FEE,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        // Mint the LP
        (lpTokenId, , , ) = INonfungiblePositionManager(nonfungiblePositionManager).mint(params);
    }

    /// @dev Handles incoming currency for buy orders, either ETH/WETH or ERC20 tokens
    /// @param orderSize The total size of the order in the currency
    /// @param trueOrderSize The actual amount being used for the swap after fees
    function _handleIncomingCurrency(uint256 orderSize, uint256 trueOrderSize) internal {
        if (currency == WETH) {
            if (msg.value != orderSize) {
                revert EthAmountMismatch();
            }

            if (msg.value < MIN_ORDER_SIZE) {
                revert EthAmountTooSmall();
            }

            IWETH(WETH).deposit{value: trueOrderSize}();
            IWETH(WETH).approve(swapRouter, trueOrderSize);
        } else {
            // Ensure ETH is not sent with a non-ETH pair
            if (msg.value != 0) {
                revert EthTransferInvalid();
            }

            uint256 beforeBalance = IERC20(currency).balanceOf(address(this));
            IERC20(currency).safeTransferFrom(msg.sender, address(this), orderSize);
            uint256 afterBalance = IERC20(currency).balanceOf(address(this));

            if ((afterBalance - beforeBalance) != orderSize) {
                revert ERC20TransferAmountMismatch();
            }

            IERC20(currency).approve(swapRouter, trueOrderSize);
        }
    }

    /// @dev Handles sending ETH and ERC20 payouts from sell orders to recipients
    /// @param orderPayout The amount of currency to pay out
    /// @param recipient The address to receive the payout
    function _handleSellPayout(uint256 orderPayout, address recipient) internal {
        if (currency == WETH) {
            Address.sendValue(payable(recipient), orderPayout);
        } else {
            IERC20(currency).safeTransfer(recipient, orderPayout);
        }
    }

    /// @dev Handles calculating and depositing fees to an escrow protocol rewards contract
    function _handleTradeRewards(uint256 totalValue, address _tradeReferrer) internal {
        if (_tradeReferrer == address(0)) {
            _tradeReferrer = protocolRewardRecipient;
        }

        uint256 tokenCreatorFee = _calculateReward(totalValue, TOKEN_CREATOR_FEE_BPS);
        uint256 platformReferrerFee = _calculateReward(totalValue, PLATFORM_REFERRER_FEE_BPS);
        uint256 tradeReferrerFee = _calculateReward(totalValue, TRADE_REFERRER_FEE_BPS);
        uint256 protocolFee = totalValue - tokenCreatorFee - platformReferrerFee - tradeReferrerFee;

        if (currency == WETH) {
            address[] memory recipients = new address[](4);
            uint256[] memory amounts = new uint256[](4);
            bytes4[] memory reasons = new bytes4[](4);

            recipients[0] = payoutRecipient;
            amounts[0] = tokenCreatorFee;
            reasons[0] = bytes4(keccak256("COIN_CREATOR_REWARD"));

            recipients[1] = platformReferrer;
            amounts[1] = platformReferrerFee;
            reasons[1] = bytes4(keccak256("COIN_PLATFORM_REFERRER_REWARD"));

            recipients[2] = _tradeReferrer;
            amounts[2] = tradeReferrerFee;
            reasons[2] = bytes4(keccak256("COIN_TRADE_REFERRER_REWARD"));

            recipients[3] = protocolRewardRecipient;
            amounts[3] = protocolFee;
            reasons[3] = bytes4(keccak256("COIN_PROTOCOL_REWARD"));

            IProtocolRewards(protocolRewards).depositBatch{value: totalValue}(recipients, amounts, reasons, "");
        }

        if (currency != WETH) {
            IERC20(currency).safeTransfer(payoutRecipient, tokenCreatorFee);
            IERC20(currency).safeTransfer(platformReferrer, platformReferrerFee);
            IERC20(currency).safeTransfer(_tradeReferrer, tradeReferrerFee);
            IERC20(currency).safeTransfer(protocolRewardRecipient, protocolFee);
        }

        emit WowTokenFees(
            payoutRecipient,
            platformReferrer,
            _tradeReferrer,
            protocolRewardRecipient,
            tokenCreatorFee,
            platformReferrerFee,
            tradeReferrerFee,
            protocolFee
        );

        emit CoinTradeRewards(
            payoutRecipient,
            platformReferrer,
            _tradeReferrer,
            protocolRewardRecipient,
            tokenCreatorFee,
            platformReferrerFee,
            tradeReferrerFee,
            protocolFee,
            address(0)
        );
    }

    function _handleMarketRewards() internal returns (MarketRewards memory) {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: lpTokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (uint256 totalAmountToken0, uint256 totalAmountToken1) = INonfungiblePositionManager(nonfungiblePositionManager).collect(params);

        address token0 = currency < address(this) ? currency : address(this);
        address token1 = currency < address(this) ? address(this) : currency;

        MarketRewards memory rewards;

        rewards = _transferMarketRewards(token0, totalAmountToken0, rewards);
        rewards = _transferMarketRewards(token1, totalAmountToken1, rewards);

        emit CoinMarketRewards(payoutRecipient, platformReferrer, protocolRewardRecipient, currency, rewards);

        return rewards;
    }

    function _transferMarketRewards(address token, uint256 totalAmount, MarketRewards memory rewards) internal returns (MarketRewards memory) {
        if (totalAmount > 0) {
            uint256 creatorPayout = _calculateReward(totalAmount, CREATOR_MARKET_REWARD_BPS);
            uint256 platformReferrerPayout = _calculateReward(totalAmount, PLATFORM_REFERRER_MARKET_REWARD_BPS);
            uint256 protocolPayout = totalAmount - creatorPayout - platformReferrerPayout;

            if (token == WETH) {
                IWETH(WETH).withdraw(totalAmount);

                rewards.totalAmountCurrency = totalAmount;
                rewards.creatorPayoutAmountCurrency = creatorPayout;
                rewards.platformReferrerAmountCurrency = platformReferrerPayout;
                rewards.protocolAmountCurrency = protocolPayout;

                address[] memory recipients = new address[](3);
                recipients[0] = payoutRecipient;
                recipients[1] = platformReferrer;
                recipients[2] = protocolRewardRecipient;

                uint256[] memory amounts = new uint256[](3);
                amounts[0] = rewards.creatorPayoutAmountCurrency;
                amounts[1] = rewards.platformReferrerAmountCurrency;
                amounts[2] = rewards.protocolAmountCurrency;

                bytes4[] memory reasons = new bytes4[](3);
                reasons[0] = bytes4(keccak256("COIN_CREATOR_MARKET_REWARD"));
                reasons[1] = bytes4(keccak256("COIN_PLATFORM_REFERRER_MARKET_REWARD"));
                reasons[2] = bytes4(keccak256("COIN_PROTOCOL_MARKET_REWARD"));

                IProtocolRewards(protocolRewards).depositBatch{value: totalAmount}(recipients, amounts, reasons, "");
            } else if (token == address(this)) {
                rewards.totalAmountCoin = totalAmount;
                rewards.creatorPayoutAmountCoin = creatorPayout;
                rewards.platformReferrerAmountCoin = platformReferrerPayout;
                rewards.protocolAmountCoin = protocolPayout;

                _transfer(address(this), payoutRecipient, rewards.creatorPayoutAmountCoin);
                _transfer(address(this), platformReferrer, rewards.platformReferrerAmountCoin);
                _transfer(address(this), protocolRewardRecipient, rewards.protocolAmountCoin);
            } else {
                rewards.totalAmountCurrency = totalAmount;
                rewards.creatorPayoutAmountCurrency = creatorPayout;
                rewards.platformReferrerAmountCurrency = platformReferrerPayout;
                rewards.protocolAmountCurrency = protocolPayout;

                IERC20(currency).safeTransfer(payoutRecipient, creatorPayout);
                IERC20(currency).safeTransfer(platformReferrer, platformReferrerPayout);
                IERC20(currency).safeTransfer(protocolRewardRecipient, protocolPayout);
            }
        }

        return rewards;
    }

    /// @dev Utility for computing amounts in basis points.
    function _calculateReward(uint256 amount, uint256 bps) internal pure returns (uint256) {
        return (amount * bps) / 10_000;
    }
}
