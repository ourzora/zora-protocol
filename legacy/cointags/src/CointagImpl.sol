// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IProtocolRewards} from "@zoralabs/shared-contracts/interfaces/IProtocolRewards.sol";
import {IWETH} from "@zoralabs/shared-contracts/interfaces/IWETH.sol";
import {IBurnableERC20} from "./interfaces/IBurnableERC20.sol";
import {IUniswapV3Pool} from "@zoralabs/shared-contracts/interfaces/uniswap/IUniswapV3Pool.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ICointag} from "./interfaces/ICointag.sol";
import {CointagStorage} from "./storage/CointagStorage.sol";
import {IUniswapV3SwapCallback} from "@zoralabs/shared-contracts/interfaces/uniswap/IUniswapV3SwapCallback.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ContractVersionBase} from "./version/ContractVersionBase.sol";
import {TickMath} from "./uniswap/TickMathLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUpgradeGate} from "@zoralabs/shared-contracts/interfaces/IUpgradeGate.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IHasContractName} from "@zoralabs/shared-contracts/interfaces/IContractMetadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

/// @title Cointag Implementation Contract
/// @notice Cointag is a protocol that enables a portion of creator rewards earned from Zora posts to be used to buy and burn an ERC20 token.
/// @dev Cointags are created for each combination of creator reward recipient, ERC20 token, and Uniswap V3 pool.
/// This contract is upgradeable by the creator using UUPS pattern and controlled by an UpgradeGate.
contract CointagImpl is
    Initializable,
    ContractVersionBase,
    CointagStorage,
    ICointag,
    IUniswapV3SwapCallback,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    IHasContractName
{
    using SafeERC20 for IERC20;

    IProtocolRewards public immutable protocolRewards;
    IWETH public immutable weth;
    IUpgradeGate public immutable upgradeGate;
    uint256 public constant PERCENTAGE_BASIS = 10_000;
    bytes4 constant REWARD_RECEIVER_REASON = bytes4(keccak256("Cointag split to creator reward recipient"));

    address internal constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    constructor(address protocolRewards_, address weth_, address upgradeGate_) {
        _requireNotAddressZero(protocolRewards_);
        _requireNotAddressZero(weth_);
        _requireNotAddressZero(upgradeGate_);

        protocolRewards = IProtocolRewards(protocolRewards_);
        weth = IWETH(weth_);
        upgradeGate = IUpgradeGate(upgradeGate_);

        // Initialize UUPS in constructor for implementation
        _disableInitializers();
    }

    /// @notice Public getter for default CointagStorageV1 settings
    function config() public pure returns (ICointag.CointagStorageV1 memory cointagStorage) {
        cointagStorage = _getCointagStorageV1();
    }

    /// @notice Public getter for associated ERC20 token
    function erc20() public view returns (IERC20) {
        return _getCointagStorageV1().erc20;
    }

    /// @notice Public getter for the associated pool
    function pool() public view returns (IUniswapV3Pool) {
        return _getCointagStorageV1().pool;
    }

    /// @notice Initializes the Cointag contract
    /// @param creatorRewardRecipient The address that will receive creator rewards
    /// @param pool_ The Uniswap V3 pool used for swapping WETH to ERC20
    /// @param percentageToBuyBurn The percentage of rewards that will be used to buy and burn tokens
    function initialize(address creatorRewardRecipient, address pool_, uint256 percentageToBuyBurn) external initializer {
        _requireNotAddressZero(creatorRewardRecipient);
        _requireNotAddressZero(pool_);

        // Initialize Ownable - creator is the owner
        __Ownable_init(creatorRewardRecipient);
        // Initialize UUPS
        __UUPSUpgradeable_init();

        CointagStorageV1 storage cointagSettings = _getCointagStorageV1();

        cointagSettings.creatorRewardRecipient = creatorRewardRecipient;
        cointagSettings.pool = IUniswapV3Pool(pool_);
        cointagSettings.percentageToBuyBurn = percentageToBuyBurn;
        cointagSettings.erc20 = IBurnableERC20(_getERC20FromPool(IUniswapV3Pool(pool_)));

        require(_onePoolTokenIsWeth(IUniswapV3Pool(pool_)), PoolNeedsOneTokenToBeWETH());
        // v2 doesn't have a fee() function, so a simple way to prevent non-v3 pools from being used
        // is to try to call it and revert if it fails
        try IUniswapV3Pool(pool_).fee() returns (uint24) {} catch {
            revert NotUniswapV3Pool();
        }

        emit Initialized({
            creatorRewardRecipient: creatorRewardRecipient,
            erc20: address(cointagSettings.erc20),
            pool: pool_,
            percentageToBuyBurn: percentageToBuyBurn
        });
    }

    /// @notice Re
    function _onePoolTokenIsWeth(IUniswapV3Pool pool_) internal view returns (bool) {
        return pool_.token0() == address(weth) || pool_.token1() == address(weth);
    }

    /// @notice Get ERC20 from pool
    /// @param pool_ Pool to get ERC20 (or non-WETH) token from
    function _getERC20FromPool(IUniswapV3Pool pool_) internal view returns (address) {
        address token0 = pool_.token0();
        return token0 == address(weth) ? pool_.token1() : token0;
    }

    /// @notice Pulls rewards from protocol rewards and pushes them through the distribution flow
    function pull() external {
        // withdraw funds from protocol rewards to this contract
        protocolRewards.withdraw(address(this), 0);
        // distribute eth received
        distribute();
    }

    /// @notice Function to receive arbitrary ETH for better API compat
    receive() external payable {
        emit EthReceived(msg.value, msg.sender);
    }

    /// @notice Distributes ETH currently held by the contract to buy and burn tokens and pay the creator
    /// @dev This function is called automatically when pulling.
    /// @dev but can also be called manually to distribute any ETH held by the contract if it was sent separately.
    function distribute() public {
        // attempt to buy/burn. remaining amount after attempted buy/burn is returned.
        _buyBurn();

        // send remaining eth to creator reward recipient
        if (address(this).balance > 0) {
            protocolRewards.deposit{value: address(this).balance}(
                _getCointagStorageV1().creatorRewardRecipient,
                REWARD_RECEIVER_REASON,
                "Cointag split to creator reward recipient"
            );
        }
    }

    /// @notice Internal function to execute buyBurn action
    /// @return amountToSendToCreator Amount that should be sent to the creator
    function _buyBurn() internal returns (uint256 amountToSendToCreator) {
        uint256 amount = address(this).balance;
        uint256 amountToBuyBurn = (amount * _getCointagStorageV1().percentageToBuyBurn) / PERCENTAGE_BASIS;
        uint256 amountERC20Burned;
        bytes memory burnFailureError;

        // Step 1: Wrap ETH and approve WETH
        weth.deposit{value: amountToBuyBurn}();

        // Step 2: Swap WETH for ERC20
        bytes memory buyFailureError = _swapWETHForERC20(amountToBuyBurn);

        // If swap failed, unwind and return
        if (buyFailureError.length > 0) {
            // transfer failed weth to creator
            IERC20(address(weth)).safeTransfer(_getCointagStorageV1().creatorRewardRecipient, amountToBuyBurn);

            // if swap fails, we want to send the entire amount to the creator reward recipient
            amountToSendToCreator = amount;
            emit BuyBurn(0, 0, amountToBuyBurn, amountToSendToCreator, amount, buyFailureError, "");
        } else {
            // amount remaining is the amount that was not used to buy/burn, that should transfer to the creator reward recipient
            amountToSendToCreator = amount - amountToBuyBurn;

            uint256 amountERC20Received = _getCointagStorageV1().erc20.balanceOf(address(this));

            // Step 3: Burn ERC20
            (amountERC20Burned, burnFailureError) = _tryBurnERC20(amountERC20Received);

            emit BuyBurn({
                amountERC20Received: amountERC20Received,
                amountERC20Burned: amountERC20Burned,
                amountETHSpent: amountToBuyBurn,
                amountETHToCreator: amountToSendToCreator,
                totalETHReceived: amount,
                buyFailureError: buyFailureError,
                burnFailureError: burnFailureError
            });
        }
    }

    /// @notice Internal function to swap WETH for the ERC20 desired
    /// @param amountIn The amount of WETH to execute the swap for
    /// @return swapError Error encountered during a swap
    function _swapWETHForERC20(uint256 amountIn) internal returns (bytes memory swapError) {
        IUniswapV3Pool pool_ = _getCointagStorageV1().pool;
        bool zeroForOne = address(weth) == pool_.token0();

        // code copied from https://github.com/Uniswap/swap-router-contracts/blob/main/contracts/V3SwapRouter.sol#L96
        uint160 sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1;

        try
            pool_.swap(
                address(this),
                zeroForOne,
                int256(amountIn),
                sqrtPriceLimitX96,
                "" // No callback data needed
            )
        returns (int256, int256) {} catch (bytes memory err) {
            // The error needs to be set to mark this swap failed. In the case of no err setting, this sets a default.
            if (err.length == 0) {
                err = abi.encodeWithSelector(UnknownSwapError.selector);
            }
            swapError = err;
        }
    }

    /// @notice Attempt to burn ERC20 internal function
    /// @param amount Amount to burn
    /// @return amountBurned token amount burned
    /// @return burnError set if there was an error attempting to burn the tokens
    function _tryBurnERC20(uint256 amount) internal returns (uint256 amountBurned, bytes memory burnError) {
        IERC20 erc20_ = _getCointagStorageV1().erc20;

        try IBurnableERC20(address(erc20_)).burn(amount) {
            amountBurned = amount;
        } catch (bytes memory err) {
            burnError = err;

            (bool success, bytes memory transferErr) = _trySafeTransfer(erc20_, DEAD_ADDRESS, amount);
            if (success) {
                amountBurned = amount;
            } else {
                burnError = transferErr;
                // The error needs to be set to mark this swap failed. In the case of no err setting, this sets a default.
                if (burnError.length == 0) {
                    burnError = abi.encodeWithSelector(UnknownBurnError.selector);
                }
                amountBurned = 0;
            }
        }
    }

    /// @notice Try to safe transfer a token
    /// @dev similar to SafeERC20.safeTransfer, but doesn't revert if the transfer fails
    /// @param token token to attempt to transfer
    /// @param to address to receive the token safe transfer
    /// @param amount amount to attempt to transfer
    /// @return success if the attempted transfer was successful
    /// @return data Data returned from the transfer
    function _trySafeTransfer(IERC20 token, address to, uint256 amount) private returns (bool success, bytes memory data) {
        // code extracted from SafeERC20.safeTransfer
        (success, data) = address(token).call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        success = success && (data.length == 0 || abi.decode(data, (bool)));
    }

    /// @notice Function to allow UniswapV3Swap
    /// @param amount0Delta token 0 delta parameter to send tokens
    /// @param amount1Delta token 1 delta parameter to send tokens
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        // no-op to allow swap
        require(msg.sender == address(_getCointagStorageV1().pool), OnlyPool());

        if (amount0Delta > 0) {
            IERC20(address(weth)).safeTransfer(msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            IERC20(address(weth)).safeTransfer(msg.sender, uint256(amount1Delta));
        }
    }

    /// @notice Helper function to ensure the passed address is not equal to zero
    function _requireNotAddressZero(address _address) internal pure {
        if (_address == address(0)) {
            revert AddressZero();
        }
    }

    /// @notice ContractName getter primarily used for upgrade checks and developers
    /// @return name Name of the contract
    function contractName() external pure override(ICointag, IHasContractName) returns (string memory) {
        return "Cointag";
    }

    /// @notice Underlying implementation getter
    /// @return address of the underling upgrade implementation
    function implementation() public view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /// @notice Upgradeable openzeppelin authorize upgrade function
    /// @param _newImpl new implementation to attempt to upgrade to
    function _authorizeUpgrade(address _newImpl) internal override onlyOwner {
        // Verify contract name matches
        string memory newName = IHasContractName(_newImpl).contractName();
        string memory currentName = this.contractName();
        require(Strings.equal(newName, currentName), UpgradeToMismatchedContractName(currentName, newName));

        // Verify upgrade path is registered in upgrade gate
        address _currentImpl = implementation();
        require(upgradeGate.isRegisteredUpgradePath(_currentImpl, _newImpl), InvalidUpgradePath(_currentImpl, _newImpl));
    }
}
