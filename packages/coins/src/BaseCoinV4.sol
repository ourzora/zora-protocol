// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {IPoolManager, PoolKey, Currency, IHooks} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {BaseCoin} from "./BaseCoin.sol";
import {ICoinV4, IHasPoolKey, IHasSwapPath} from "./interfaces/ICoinV4.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {PoolConfiguration} from "./types/PoolConfiguration.sol";
import {UniV4SwapToCurrency} from "./libs/UniV4SwapToCurrency.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {IDeployedCoinVersionLookup} from "./interfaces/IDeployedCoinVersionLookup.sol";
import {CoinConstants} from "./libs/CoinConstants.sol";
import {IUpgradeableV4Hook} from "./interfaces/IUpgradeableV4Hook.sol";
import {CoinCommon} from "./libs/CoinCommon.sol";

/**
 * @title BaseCoinV4
 * @notice Abstract base contract for Uniswap V4 integrated coins
 * @dev Provides shared V4 functionality for both content coins and creator coins
 */
abstract contract BaseCoinV4 is BaseCoin, ICoinV4 {
    /// @notice The Uniswap v4 pool manager singleton contract reference.
    IPoolManager public immutable poolManager;

    /// @notice The pool key for the coin. Type from Uniswap V4 core.
    PoolKey internal poolKey;

    /// @notice The configuration for the pool.
    PoolConfiguration internal poolConfiguration;

    /// @notice The constructor for the static BaseCoinV4 contract deployment shared across all Coins.
    /// @dev All arguments are required and cannot be set to the 0 address.
    /// @param protocolRewardRecipient_ The address of the protocol reward recipient
    /// @param protocolRewards_ The address of the protocol rewards contract
    /// @param poolManager_ The address of the pool manager
    /// @param airlock_ The address of the Airlock contract, ownership is used for a protocol fee split.
    /// @notice Returns the pool key for the coin
    constructor(
        address protocolRewardRecipient_,
        address protocolRewards_,
        IPoolManager poolManager_,
        address airlock_
    ) BaseCoin(protocolRewardRecipient_, protocolRewards_, airlock_) {
        if (address(poolManager_) == address(0)) {
            revert AddressZero();
        }

        poolManager = poolManager_;
    }

    /// @inheritdoc IHasPoolKey
    function getPoolKey() public view returns (PoolKey memory) {
        return poolKey;
    }

    /// @inheritdoc ICoinV4
    function getPoolConfiguration() public view returns (PoolConfiguration memory) {
        return poolConfiguration;
    }

    /// @inheritdoc ICoinV4
    function initialize(
        address payoutRecipient_,
        address[] memory owners_,
        string memory tokenURI_,
        string memory name_,
        string memory symbol_,
        address platformReferrer_,
        address currency_,
        PoolKey memory poolKey_,
        uint160 sqrtPriceX96,
        PoolConfiguration memory poolConfiguration_
    ) public virtual initializer {
        currency = currency_;
        // we need to set this before initialization, because
        // distributing currency relies on the poolkey being set since the hooks
        // are retrieved from there
        poolKey = poolKey_;
        poolConfiguration = poolConfiguration_;

        super._initialize(payoutRecipient_, owners_, tokenURI_, name_, symbol_, platformReferrer_);

        // initialize the pool - the hook will mint its positions in the afterInitialize callback
        poolManager.initialize(poolKey, sqrtPriceX96);
    }

    /// @inheritdoc ICoinV4
    function hooks() external view returns (IHooks) {
        return poolKey.hooks;
    }

    /// @notice Migrate liquidity from current hook to a new hook implementation
    /// @param newHook Address of the new hook implementation
    /// @param additionalData Additional data to pass to the new hook during initialization
    function migrateLiquidity(address newHook, bytes calldata additionalData) external onlyOwner returns (PoolKey memory newPoolKey) {
        newPoolKey = IUpgradeableV4Hook(address(poolKey.hooks)).migrateLiquidity(newHook, poolKey, additionalData);

        emit LiquidityMigrated(poolKey, CoinCommon.hashPoolKey(poolKey), newPoolKey, CoinCommon.hashPoolKey(newPoolKey));

        poolKey = newPoolKey;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(BaseCoin, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IHasPoolKey).interfaceId || type(IHasSwapPath).interfaceId == interfaceId;
    }

    /// @inheritdoc IHasSwapPath
    function getPayoutSwapPath(IDeployedCoinVersionLookup coinVersionLookup) external view returns (IHasSwapPath.PayoutSwapPath memory payoutSwapPath) {
        // if to swap in is this currency,
        // if backing currency is a coin, then recursively get the path from the coin
        payoutSwapPath.currencyIn = Currency.wrap(address(this));

        // swap to backing currency
        PathKey memory thisPathKey = PathKey({
            intermediateCurrency: Currency.wrap(currency),
            fee: poolKey.fee,
            tickSpacing: poolKey.tickSpacing,
            hooks: poolKey.hooks,
            hookData: ""
        });

        // get backing currency swap path - if the backing currency is a v4 coin and has a swap path.
        PathKey[] memory subPath = UniV4SwapToCurrency.getSubSwapPath(currency, coinVersionLookup);

        if (subPath.length > 0) {
            payoutSwapPath.path = new PathKey[](1 + subPath.length);
            payoutSwapPath.path[0] = thisPathKey;
            for (uint256 i = 0; i < subPath.length; i++) {
                payoutSwapPath.path[i + 1] = subPath[i];
            }
        } else {
            payoutSwapPath.path = new PathKey[](1);
            payoutSwapPath.path[0] = thisPathKey;
        }
    }
}
