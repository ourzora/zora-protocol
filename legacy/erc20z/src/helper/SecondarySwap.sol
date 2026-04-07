// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {ISecondarySwap} from "../interfaces/ISecondarySwap.sol";
import {IERC20Z} from "../interfaces/IERC20Z.sol";
import {ISwapRouter} from "@zoralabs/shared-contracts/interfaces/uniswap/ISwapRouter.sol";
import {IZoraTimedSaleStrategy} from "../interfaces/IZoraTimedSaleStrategy.sol";
import {IWETH} from "@zoralabs/shared-contracts/interfaces/IWETH.sol";

contract SecondarySwap is ISecondarySwap, ReentrancyGuard, IERC1155Receiver {
    uint256 internal constant ONE_ERC_20 = 1e18;

    bytes4 constant ON_ERC1155_RECEIVED_HASH = IERC1155Receiver.onERC1155Received.selector;

    IWETH public WETH;
    ISwapRouter public swapRouter;
    uint24 public uniswapFee;
    IZoraTimedSaleStrategy public zoraTimedSaleStrategy;

    /// @notice This must be called in the same transaction that the contract is created on.
    function initialize(IWETH weth_, ISwapRouter swapRouter_, uint24 uniswapFee_, IZoraTimedSaleStrategy zoraTimedSaleStrategy_) external {
        // Ensure a non-zero WETH address is passed upon initialization
        if (address(weth_) == address(0)) {
            revert AddressZero();
        }

        // Ensure this contract cannot be reinitialized
        if (address(WETH) != address(0)) {
            revert AlreadyInitialized();
        }

        WETH = weth_;
        swapRouter = swapRouter_;
        uniswapFee = uniswapFee_;
        zoraTimedSaleStrategy = zoraTimedSaleStrategy_;
    }

    /// @notice ETH -> WETH -> ERC20Z -> ERC1155
    function buy1155(
        address erc20zAddress,
        uint256 num1155ToBuy,
        address payable recipient,
        address payable excessRefundRecipient,
        uint256 maxEthToSpend,
        uint160 sqrtPriceLimitX96
    ) external payable nonReentrant {
        // Ensure the recipient address is valid
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }

        // Get the amount of ETH sent
        uint256 amountETHIn = msg.value;

        // Ensure ETH is sent with the transaction
        if (amountETHIn == 0) {
            revert NoETHSent();
        }

        // Convert ETH to WETH
        WETH.deposit{value: amountETHIn}();

        // Approve the swap router to spend WETH
        WETH.approve(address(swapRouter), amountETHIn);

        // Calculate the expected amount of ERC20Z
        uint256 expectedAmountERC20Out = num1155ToBuy * ONE_ERC_20;

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: address(WETH),
            tokenOut: erc20zAddress,
            fee: uniswapFee,
            recipient: address(this),
            amountOut: expectedAmountERC20Out,
            amountInMaximum: maxEthToSpend,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        // Execute the swap and get the amount of WETH used
        uint256 amountWethUsed = swapRouter.exactOutputSingle(params);

        // Ensure that the expected amount of ERC20Z was received
        if (IERC20Z(erc20zAddress).balanceOf(address(this)) < expectedAmountERC20Out) {
            revert ERC20ZMinimumAmountNotReceived();
        }

        // Approve the ERC20Z tokens to be converted to ERC1155s
        IERC20Z(erc20zAddress).approve(erc20zAddress, expectedAmountERC20Out);

        // Convert ERC20Z to ERC1155
        IERC20Z(erc20zAddress).unwrap(expectedAmountERC20Out, recipient);

        // If there is any excess WETH:
        if (amountWethUsed < amountETHIn) {
            // Convert the excess WETH to ETH
            WETH.withdraw(amountETHIn - amountWethUsed);

            // Refund the excess ETH to the recipient
            Address.sendValue(excessRefundRecipient, msg.value - amountWethUsed);
        }

        emit SecondaryBuy(msg.sender, recipient, erc20zAddress, amountWethUsed, num1155ToBuy);
    }

    /// @notice ERC1155 -> ERC20Z -> WETH -> ETH
    function sell1155(
        address erc20zAddress,
        uint256 num1155ToSell,
        address payable recipient,
        uint256 minEthToAcquire,
        uint160 sqrtPriceLimitX96
    ) external nonReentrant {
        IERC20Z.TokenInfo memory tokenInfo = IERC20Z(erc20zAddress).tokenInfo();

        // Transfer ERC1155 tokens from sender to this contract and wrap them
        IERC1155(tokenInfo.collection).safeTransferFrom(msg.sender, erc20zAddress, tokenInfo.tokenId, num1155ToSell, abi.encode(address(this)));

        _sell1155(erc20zAddress, num1155ToSell, recipient, minEthToAcquire, sqrtPriceLimitX96);
    }

    /// @notice ERC1155 -> ERC20Z -> WETH -> ETH
    function _sell1155(address erc20zAddress, uint256 num1155ToSell, address payable recipient, uint256 minEthToAcquire, uint160 sqrtPriceLimitX96) private {
        // Ensure the recipient is valid
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }

        // Calculate expected amount of ERC20Z
        uint256 expectedAmountERC20In = num1155ToSell * 1e18;

        // Ensure that the conversion was successful
        if (IERC20Z(erc20zAddress).balanceOf(address(this)) < expectedAmountERC20In) {
            revert ERC20ZEquivalentAmountNotConverted();
        }

        // Approve swap router to spend ERC20Z tokens
        IERC20Z(erc20zAddress).approve(address(swapRouter), expectedAmountERC20In);

        // Set up parameters for the swap from ERC20Z to WETH
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: erc20zAddress,
            tokenOut: address(WETH),
            fee: uniswapFee,
            recipient: address(this),
            amountIn: expectedAmountERC20In,
            amountOutMinimum: minEthToAcquire,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        // Execute the swap and receive WETH
        uint256 amountWethOut = swapRouter.exactInputSingle(params);

        // Convert WETH to ETH
        WETH.withdraw(amountWethOut);

        // Transfer ETH to the recipient
        Address.sendValue(recipient, amountWethOut);

        emit SecondarySell(msg.sender, recipient, erc20zAddress, amountWethOut, num1155ToSell);
    }

    /// @notice Receive transfer hook that allows to sell 1155s for eth based on the secondary market value
    function onERC1155Received(address, address, uint256 id, uint256 value, bytes calldata data) external override nonReentrant returns (bytes4) {
        address collection = msg.sender;

        uint256 num1155ToSell = value;

        (address payable recipient, uint256 minEthToAcquire, uint160 sqrtPriceLimitX96) = abi.decode(data, (address, uint256, uint160));

        address erc20zAddress = zoraTimedSaleStrategy.sale(collection, id).erc20zAddress;

        if (erc20zAddress == address(0)) {
            revert SaleNotSet();
        }

        // assume this contract has 1155s, transfer them to the erc20z and wrap them
        IERC1155(collection).safeTransferFrom(address(this), erc20zAddress, id, num1155ToSell, abi.encode(address(this)));

        _sell1155(erc20zAddress, num1155ToSell, recipient, minEthToAcquire, sqrtPriceLimitX96);

        return ON_ERC1155_RECEIVED_HASH;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure override returns (bytes4) {
        revert NotSupported();
    }

    receive() external payable {
        if (msg.sender != address(WETH)) {
            revert OnlyWETH();
        }
    }
}
