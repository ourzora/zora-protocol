// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {V4TestSetup} from "./V4TestSetup.sol";
import "forge-std/Test.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IZoraFactory} from "../../src/interfaces/IZoraFactory.sol";
import {ZoraFactoryImpl} from "../../src/ZoraFactoryImpl.sol";
import {ZoraFactory} from "../../src/proxy/ZoraFactory.sol";
import {ContentCoin} from "../../src/ContentCoin.sol";
import {MultiOwnable} from "../../src/utils/MultiOwnable.sol";
import {ICoin} from "../../src/interfaces/ICoin.sol";
import {IERC7572} from "../../src/interfaces/IERC7572.sol";
import {IWETH} from "../../src/interfaces/IWETH.sol";
import {IAirlock} from "../../src/interfaces/IAirlock.sol";
import {INonfungiblePositionManager} from "../../src/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "../../src/interfaces/ISwapRouter.sol";
import {IUniswapV3Factory} from "../../src/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../../src/interfaces/IUniswapV3Pool.sol";
import {IProtocolRewards} from "../../src/interfaces/IProtocolRewards.sol";
import {ProtocolRewards} from "../utils/ProtocolRewards.sol";
import {CoinConfigurationVersions} from "../../src/libs/CoinConfigurationVersions.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {ZoraV4CoinHook} from "../../src/hooks/ZoraV4CoinHook.sol";
import {HooksDeployment} from "../../src/libs/HooksDeployment.sol";
import {CoinConstants} from "../../src/libs/CoinConstants.sol";
import {ProxyShim} from "../../src/utils/ProxyShim.sol";
import {ICoin} from "../../src/interfaces/ICoin.sol";
import {UniV4SwapHelper} from "../../src/libs/UniV4SwapHelper.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IUniversalRouter} from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import {IV4Quoter} from "@uniswap/v4-periphery/src/interfaces/IV4Quoter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CreatorCoin} from "../../src/CreatorCoin.sol";
import {ContractAddresses} from "./ContractAddresses.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {HookUpgradeGate} from "../../src/hooks/HookUpgradeGate.sol";
import {ZoraHookRegistry} from "../../src/hook-registry/ZoraHookRegistry.sol";
import {TrustedMsgSenderProviderLookup} from "../../src/utils/TrustedMsgSenderProviderLookup.sol";
import {ITrustedMsgSenderProviderLookup} from "../../src/interfaces/ITrustedMsgSenderProviderLookup.sol";
import {TrustedSenderTestHelper} from "./TrustedSenderTestHelper.sol";

// Hookmate imports for non-forked testing
import {V4PoolManagerDeployer} from "./hookmate/artifacts/V4PoolManager.sol";
import {V4QuoterDeployer} from "./hookmate/artifacts/V4Quoter.sol";
import {Permit2Deployer} from "./hookmate/artifacts/Permit2.sol";
import {DeployHelper} from "./hookmate/artifacts/DeployHelper.sol";
import {AddressConstants} from "./hookmate/constants/AddressConstants.sol";
import {UniversalRouterDeployer, RouterParameters} from "./hookmate/artifacts/UniversalRouter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAirlock} from "../mocks/MockAirlock.sol";
import {SimpleERC20} from "../mocks/SimpleERC20.sol";

/**
 * @title BaseTest
 * @notice Coins-specific test utilities extending V4TestSetup
 * @dev This contract adds coins-specific reward calculations on top of shared V4 infrastructure
 */
contract BaseTest is V4TestSetup {
    function setUp() public virtual {
        setUpWithBlockNumber(28415528);
    }

    function setUpWithBlockNumber(uint256 forkBlockNumber) public virtual {
        _setUpWithBlockNumber(forkBlockNumber);
    }

    function setUpNonForked() public virtual {
        _setUpNonForked();
    }

    function setUpNonForked(address limitOrderBook) public virtual {
        _setUpNonForked(limitOrderBook);
    }

    struct TradeRewards {
        uint256 creator;
        uint256 platformReferrer;
        uint256 tradeReferrer;
        uint256 protocol;
    }

    struct MarketRewards {
        uint256 creator;
        uint256 platformReferrer;
        uint256 doppler;
        uint256 protocol;
    }

    function _calculateTradeRewards(uint256 ethAmount) internal pure returns (TradeRewards memory) {
        return
            TradeRewards({
                creator: (ethAmount * 5000) / 10_000,
                platformReferrer: (ethAmount * 1500) / 10_000,
                tradeReferrer: (ethAmount * 1500) / 10_000,
                protocol: (ethAmount * 2000) / 10_000
            });
    }

    function _calculateMarketRewards(uint256 ethAmount) internal pure returns (MarketRewards memory) {
        uint256 creator = (ethAmount * 5000) / 10_000;
        uint256 platformReferrer = (ethAmount * 2500) / 10_000;
        uint256 doppler = (ethAmount * 500) / 10_000;
        uint256 protocol = ethAmount - creator - platformReferrer - doppler;

        return MarketRewards({creator: creator, platformReferrer: platformReferrer, doppler: doppler, protocol: protocol});
    }
}
