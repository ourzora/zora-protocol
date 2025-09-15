// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CoinConfigurationVersions} from "./libs/CoinConfigurationVersions.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {IZoraFactory} from "./interfaces/IZoraFactory.sol";
import {IHasAfterCoinDeploy} from "./hooks/deployment/BaseCoinDeployHook.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ICoin, PoolKeyStruct} from "./interfaces/ICoin.sol";
import {ICoin} from "./interfaces/ICoin.sol";
import {IHasContractName} from "@zoralabs/shared-contracts/interfaces/IContractMetadata.sol";
import {ContractVersionBase} from "./version/ContractVersionBase.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {CoinCommon} from "./libs/CoinCommon.sol";
import {PoolConfiguration} from "./types/PoolConfiguration.sol";
import {LpPosition} from "./types/LpPosition.sol";
import {IVersionedContract} from "@zoralabs/shared-contracts/interfaces/IVersionedContract.sol";
import {CoinSetup} from "./libs/CoinSetup.sol";
import {CoinDopplerMultiCurve} from "./libs/CoinDopplerMultiCurve.sol";
import {ICreatorCoin} from "./interfaces/ICreatorCoin.sol";
import {MarketConstants} from "./libs/MarketConstants.sol";
import {DeployedCoinVersionLookup} from "./utils/DeployedCoinVersionLookup.sol";
import {IZoraHookRegistry} from "./interfaces/IZoraHookRegistry.sol";

contract ZoraFactoryImpl is
    IZoraFactory,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable,
    Ownable2StepUpgradeable,
    IHasContractName,
    ContractVersionBase,
    DeployedCoinVersionLookup
{
    using SafeERC20 for IERC20;

    /// @notice The ZORA coin contract implementation address
    address public immutable coinV4Impl;
    /// @notice The creator coin contract implementation address
    address public immutable creatorCoinImpl;
    /// @notice The uniswap v4 coin hook address
    address public immutable hook;
    /// @notice The zora hook registry address
    address public immutable zoraHookRegistry;

    constructor(address coinV4Impl_, address creatorCoinImpl_, address hook_, address zoraHookRegistry_) {
        _disableInitializers();

        coinV4Impl = coinV4Impl_;
        creatorCoinImpl = creatorCoinImpl_;
        hook = hook_;
        zoraHookRegistry = zoraHookRegistry_;
    }

    /// @notice Creates a new creator coin contract
    /// @param payoutRecipient The recipient of creator reward payouts; this can be updated by an owner
    /// @param owners The list of addresses that will be able to manage the coin's payout address and metadata uri
    /// @param uri The coin metadata uri
    /// @param name The name of the coin
    /// @param symbol The symbol of the coin
    /// @param poolConfig The config parameters for the coin's pool
    /// @param platformReferrer The address of the platform referrer
    /// @param coinSalt The salt used to deploy the coin
    function deployCreatorCoin(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        bytes32 coinSalt
    ) public nonReentrant returns (address) {
        bytes32 salt = _buildSalt(msg.sender, name, symbol, poolConfig, platformReferrer, coinSalt);

        uint8 version = CoinConfigurationVersions.getVersion(poolConfig);

        require(version == CoinConfigurationVersions.DOPPLER_MULTICURVE_UNI_V4_POOL_VERSION, InvalidConfig());

        address creatorCoin = Clones.cloneDeterministic(creatorCoinImpl, salt);

        _setVersionForDeployedCoin(address(creatorCoin), version);

        (, address currency, uint160 sqrtPriceX96, bool isCoinToken0, PoolConfiguration memory poolConfiguration) = CoinSetup.generatePoolConfig(
            address(creatorCoin),
            poolConfig
        );

        PoolKey memory poolKey = CoinSetup.buildPoolKey(address(creatorCoin), currency, isCoinToken0, IHooks(hook));

        ICreatorCoin(creatorCoin).initialize(payoutRecipient, owners, uri, name, symbol, platformReferrer, currency, poolKey, sqrtPriceX96, poolConfiguration);

        emit CreatorCoinCreated(
            msg.sender,
            payoutRecipient,
            platformReferrer,
            currency,
            uri,
            name,
            symbol,
            address(creatorCoin),
            poolKey,
            CoinCommon.hashPoolKey(poolKey),
            IVersionedContract(address(creatorCoin)).contractVersion()
        );

        return creatorCoin;
    }

    /// @inheritdoc IZoraFactory
    function deploy(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        address postDeployHook,
        bytes calldata postDeployHookData,
        bytes32 coinSalt
    ) external payable returns (address coin, bytes memory postDeployHookDataOut) {
        bytes32 salt = _buildSalt(msg.sender, name, symbol, poolConfig, platformReferrer, coinSalt);
        return _deployWithHook(payoutRecipient, owners, uri, name, symbol, poolConfig, platformReferrer, postDeployHook, postDeployHookData, salt);
    }

    /// @inheritdoc IZoraFactory
    function coinAddress(
        address msgSender,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        bytes32 coinSalt
    ) external view returns (address) {
        bytes32 salt = _buildSalt(msgSender, name, symbol, poolConfig, platformReferrer, coinSalt);
        return Clones.predictDeterministicAddress(getCoinImpl(CoinConfigurationVersions.getVersion(poolConfig)), salt, address(this));
    }

    /// @dev Internal function to deploy a coin with a hook
    function _deployWithHook(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        address deployHook,
        bytes calldata hookData,
        bytes32 salt
    ) internal returns (address coin, bytes memory hookDataOut) {
        coin = address(_createAndInitializeCoin(payoutRecipient, owners, uri, name, symbol, poolConfig, platformReferrer, salt));

        if (deployHook != address(0)) {
            if (!IERC165(deployHook).supportsInterface(type(IHasAfterCoinDeploy).interfaceId)) {
                revert InvalidHook();
            }
            hookDataOut = IHasAfterCoinDeploy(deployHook).afterCoinDeploy{value: msg.value}(msg.sender, ICoin(coin), hookData);
        } else if (msg.value > 0) {
            // cannot send eth without a hook
            revert EthTransferInvalid();
        }
    }

    /**
     * Deprecated deploy functions
     */

    /// @dev Deprecated: use `deploy` instead that has a salt and hook specified
    function deploy(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        uint256 /*orderSize*/
    ) public payable nonReentrant returns (address, uint256) {
        bytes32 salt = _randomSalt(payoutRecipient, uri, bytes32(0));

        ICoin coin = _createAndInitializeCoin(payoutRecipient, owners, uri, name, symbol, poolConfig, platformReferrer, salt);

        uint256 coinsPurchased = 0;

        return (address(coin), coinsPurchased);
    }

    /// @dev Deprecated: use `deploy` instead that has a salt and hook specified
    function deployWithHook(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        address deployHook,
        bytes calldata hookData
    ) public payable nonReentrant returns (address coin, bytes memory hookDataOut) {
        bytes32 salt = _randomSalt(payoutRecipient, uri, bytes32(0));
        return _deployWithHook(payoutRecipient, owners, uri, name, symbol, poolConfig, platformReferrer, deployHook, hookData, salt);
    }

    /// @dev deprecated Use deploy() with poolConfig instead
    function deploy(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        address platformReferrer,
        address currency,
        // tickLower is no longer used
        int24 /* tickLower */,
        // orderSize is no longer used
        uint256 /* orderSize */
    ) public payable nonReentrant returns (address, uint256) {
        bytes memory poolConfig = CoinConfigurationVersions.defaultConfig(currency);
        bytes32 salt = _randomSalt(payoutRecipient, uri, bytes32(0));

        ICoin coin = _createAndInitializeCoin(payoutRecipient, owners, uri, name, symbol, poolConfig, platformReferrer, salt);

        return (address(coin), 0);
    }

    /**
     * End Deprecated deploy functions
     */

    function getCoinImpl(uint8 version) internal view returns (address) {
        if (CoinConfigurationVersions.isV4(version)) {
            return coinV4Impl;
        }

        revert ICoin.InvalidPoolVersion();
    }

    function _createCoin(uint8 version, bytes32 salt) internal returns (address payable) {
        return payable(Clones.cloneDeterministic(getCoinImpl(version), salt));
    }

    function _setupV4Coin(
        ICoin coin,
        address currency,
        bool isCoinToken0,
        uint160 sqrtPriceX96,
        PoolConfiguration memory poolConfiguration,
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        address platformReferrer
    ) internal {
        PoolKey memory poolKey = CoinSetup.buildPoolKey(address(coin), currency, isCoinToken0, IHooks(hook));

        // Initialize coin with pre-configured pool
        coin.initialize(payoutRecipient, owners, uri, name, symbol, platformReferrer, currency, poolKey, sqrtPriceX96, poolConfiguration);

        emit CoinCreatedV4(
            msg.sender,
            payoutRecipient,
            platformReferrer,
            currency,
            uri,
            name,
            symbol,
            address(coin),
            poolKey,
            CoinCommon.hashPoolKey(poolKey),
            IVersionedContract(address(coin)).contractVersion()
        );
    }

    function _createAndInitializeCoin(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        bytes32 coinSalt
    ) internal returns (ICoin) {
        uint8 version = CoinConfigurationVersions.getVersion(poolConfig);

        address payable coin = _createCoin(version, coinSalt);

        _setVersionForDeployedCoin(address(coin), version);

        (, address currency, uint160 sqrtPriceX96, bool isCoinToken0, PoolConfiguration memory poolConfiguration) = CoinSetup.generatePoolConfig(
            address(coin),
            poolConfig
        );

        if (CoinConfigurationVersions.isV3(version)) {
            // V3 is no longer supported
            revert ICoin.InvalidPoolVersion();
        } else if (CoinConfigurationVersions.isV4(version)) {
            _setupV4Coin(ICoin(coin), currency, isCoinToken0, sqrtPriceX96, poolConfiguration, payoutRecipient, owners, uri, name, symbol, platformReferrer);
        } else {
            revert ICoin.InvalidPoolVersion();
        }

        return ICoin(coin);
    }

    function _buildSalt(
        address msgSender,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        bytes32 coinSalt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(msgSender, name, symbol, poolConfig, platformReferrer, coinSalt));
    }

    function _randomSalt(address payoutRecipient, string memory uri, bytes32 coinSalt) internal view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    msg.sender,
                    payoutRecipient,
                    keccak256(abi.encodePacked(uri)),
                    block.coinbase,
                    block.number,
                    block.prevrandao,
                    block.timestamp,
                    tx.gasprice,
                    tx.origin,
                    coinSalt
                )
            );
    }

    /// @notice Initializes the factory proxy contract
    /// @param initialOwner Address of the contract owner
    /// @dev Can only be called once due to initializer modifier
    function initialize(address initialOwner) external initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Ownable_init(initialOwner);
    }

    /// @notice The implementation address of the factory contract
    function implementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /// @inheritdoc IHasContractName
    function contractName() public pure override returns (string memory) {
        return "ZoraCoinFactory";
    }

    /// @dev Authorizes an upgrade to a new implementation
    /// @param newImpl The new implementation address
    function _authorizeUpgrade(address newImpl) internal override onlyOwner {
        // try to get the existing contract name - if it reverts, the existing contract was an older version that didn't have the contract name
        // unfortunately we cannot use supportsInterface here because the existing implementation did not have that function
        try IHasContractName(newImpl).contractName() returns (string memory name) {
            if (!Strings.equal(name, contractName())) {
                revert UpgradeToMismatchedContractName(contractName(), name);
            }
        } catch {}

        // Auto-register the new hooks in the Zora hook registry
        address[] memory hooks = new address[](1);
        string[] memory tags = new string[](1);

        hooks[0] = IZoraFactory(newImpl).hook();
        tags[0] = "CoinHook";

        IZoraHookRegistry(zoraHookRegistry).registerHooks(hooks, tags);
    }

    /// @notice The address of the latest creator coin hook
    /// @dev Deprecated: use `hook` instead
    function creatorCoinHook() external view returns (address) {
        return hook;
    }

    /// @notice The address of the latest coin hook
    /// @dev Deprecated: use `hook` instead
    function contentCoinHook() external view returns (address) {
        return hook;
    }
}
