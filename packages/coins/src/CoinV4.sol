// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IPoolManager, PoolKey, Currency, IHooks} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {BaseCoin} from "./BaseCoin.sol";
import {LpPosition} from "./types/LpPosition.sol";
import {HooksDeployment} from "./libs/HooksDeployment.sol";
import {IHookDeployer} from "./libs/HooksDeployment.sol";
import {ZoraV4CoinHook} from "./hooks/ZoraV4CoinHook.sol";
import {ICoinV4} from "./interfaces/ICoinV4.sol";
import {V4Liquidity} from "./libs/V4Liquidity.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {CoinRewardsV4} from "./libs/CoinRewardsV4.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {PoolConfiguration} from "./types/PoolConfiguration.sol";

contract CoinV4 is BaseCoin, ICoinV4 {
    /// @notice The Uniswap v4 pool manager singleton contract reference.
    IPoolManager public immutable poolManager;

    /// @notice The hooks contract used by this coin.
    IHooks public immutable hooks;

    /// @notice The pool key for the coin. Type from Uniswap V4 core.
    PoolKey private poolKey;

    /// @notice The configuration for the pool.
    PoolConfiguration private poolConfiguration;

    /// @notice The constructor for the static CoinV4 contract deployment shared across all Coins.
    /// @dev All arguments are required and cannot be set to teh 0 address.
    /// @param protocolRewardRecipient_ The address of the protocol reward recipient
    /// @param protocolRewards_ The address of the protocol rewards contract
    /// @param poolManager_ The address of the pool manager
    /// @param airlock_ The address of the Airlock contract, ownership is used for a protocol fee split.
    /// @param hooks_ The address of the hooks contract
    /// @notice Returns the pool key for the coin
    constructor(
        address protocolRewardRecipient_,
        address protocolRewards_,
        IPoolManager poolManager_,
        address airlock_,
        IHooks hooks_
    ) BaseCoin(protocolRewardRecipient_, protocolRewards_, airlock_) {
        if (address(poolManager_) == address(0)) {
            revert AddressZero();
        }
        if (address(hooks_) == address(0)) {
            revert AddressZero();
        }

        poolManager = poolManager_;
        hooks = hooks_;
    }

    /// @inheritdoc ICoinV4
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
    ) public initializer {
        super._initialize(payoutRecipient_, owners_, tokenURI_, name_, symbol_, platformReferrer_);

        currency = currency_;
        poolKey = poolKey_;
        poolConfiguration = poolConfiguration_;

        // transfer the supply to the hook
        _transfer(address(this), address(hooks), balanceOf(address(this)));
        // initialize the pool - the hook will mint its positions in the afterInitialize callback
        poolManager.initialize(poolKey, sqrtPriceX96);
    }
}
