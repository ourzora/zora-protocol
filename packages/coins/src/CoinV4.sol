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
    IPoolManager public immutable poolManager;
    IHooks public immutable hooks;

    PoolKey private poolKey;

    PoolConfiguration private poolConfiguration;

    constructor(
        address _protocolRewardRecipient,
        address _protocolRewards,
        address _poolManager,
        address _airlock,
        IHooks _hooks
    ) BaseCoin(_protocolRewardRecipient, _protocolRewards, _airlock) {
        poolManager = IPoolManager(_poolManager);
        hooks = _hooks;
    }

    function getPoolKey() public view returns (PoolKey memory) {
        return poolKey;
    }

    function getPoolConfiguration() public view returns (PoolConfiguration memory) {
        return poolConfiguration;
    }

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
