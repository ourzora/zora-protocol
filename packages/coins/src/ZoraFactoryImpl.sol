// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
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
import {Coin} from "./Coin.sol";
import {CoinV4} from "./CoinV4.sol";
import {ICoin, PoolKeyStruct} from "./interfaces/ICoin.sol";
import {ICoinV3} from "./interfaces/ICoinV3.sol";
import {ICoinV4} from "./interfaces/ICoinV4.sol";
import {IHasContractName} from "@zoralabs/shared-contracts/interfaces/IContractMetadata.sol";
import {ContractVersionBase} from "./version/ContractVersionBase.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {CoinCommon} from "./libs/CoinCommon.sol";
import {UniV3Config} from "./libs/CoinSetupV3.sol";
import {CoinSetupV3} from "./libs/CoinSetupV3.sol";
import {PoolConfiguration} from "./types/PoolConfiguration.sol";
import {LpPosition} from "./types/LpPosition.sol";
import {IVersionedContract} from "@zoralabs/shared-contracts/interfaces/IVersionedContract.sol";
import {CoinSetup} from "./libs/CoinSetup.sol";
import {CoinDopplerMultiCurve} from "./libs/CoinDopplerMultiCurve.sol";

contract ZoraFactoryImpl is IZoraFactory, UUPSUpgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable, IHasContractName, ContractVersionBase {
    using SafeERC20 for IERC20;

    /// @notice The coin contract implementation address
    address public immutable coinImpl;
    address public immutable coinV4Impl;

    constructor(address _coinImpl, address _coinV4Impl) initializer {
        coinImpl = _coinImpl;
        coinV4Impl = _coinV4Impl;
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

    function _deployWithHook(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        address hook,
        bytes calldata hookData,
        bytes32 salt
    ) internal returns (address coin, bytes memory hookDataOut) {
        coin = address(_createAndInitializeCoin(payoutRecipient, owners, uri, name, symbol, poolConfig, platformReferrer, salt));

        if (hook != address(0)) {
            if (!IERC165(hook).supportsInterface(type(IHasAfterCoinDeploy).interfaceId)) {
                revert InvalidHook();
            }
            hookDataOut = IHasAfterCoinDeploy(hook).afterCoinDeploy{value: msg.value}(msg.sender, ICoin(coin), hookData);
        } else if (msg.value > 0) {
            // cannot send eth without a hook
            revert EthTransferInvalid();
        }
    }

    /** Deprecated deploy functions */

    /// @dev Deprecated: use `deploy` instead that has a salt and hook specified
    function deploy(
        address payoutRecipient,
        address[] memory owners,
        string memory uri,
        string memory name,
        string memory symbol,
        bytes memory poolConfig,
        address platformReferrer,
        uint256 orderSize
    ) public payable nonReentrant returns (address, uint256) {
        bytes32 salt = _randomSalt(payoutRecipient, uri, bytes32(0));

        ICoin coin = _createAndInitializeCoin(payoutRecipient, owners, uri, name, symbol, poolConfig, platformReferrer, salt);

        uint256 coinsPurchased = _handleFirstOrder(coin, orderSize);

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
        address hook,
        bytes calldata hookData
    ) public payable nonReentrant returns (address coin, bytes memory hookDataOut) {
        bytes32 salt = _randomSalt(payoutRecipient, uri, bytes32(0));
        return _deployWithHook(payoutRecipient, owners, uri, name, symbol, poolConfig, platformReferrer, hook, hookData, salt);
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
        int24 /*tickLower*/,
        uint256 orderSize
    ) public payable nonReentrant returns (address, uint256) {
        bytes memory poolConfig = CoinConfigurationVersions.defaultConfig(currency);
        bytes32 salt = _randomSalt(payoutRecipient, uri, bytes32(0));

        ICoin coin = _createAndInitializeCoin(payoutRecipient, owners, uri, name, symbol, poolConfig, platformReferrer, salt);

        uint256 coinsPurchased = _handleFirstOrder(coin, orderSize);

        return (address(coin), coinsPurchased);
    }

    function getCoinImpl(uint8 version) internal view returns (address) {
        if (CoinConfigurationVersions.isV3(version)) {
            return coinImpl;
        } else if (CoinConfigurationVersions.isV4(version)) {
            return coinV4Impl;
        }

        revert ICoin.InvalidPoolVersion();
    }

    function _createCoin(uint8 version, bytes32 salt) internal returns (address payable) {
        return payable(Clones.cloneDeterministic(getCoinImpl(version), salt));
    }

    function _setupV3Coin(
        ICoinV3 coin,
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
        address v3Factory = coin.v3Factory();

        address poolAddress = CoinSetupV3.createV3Pool(address(coin), currency, isCoinToken0, sqrtPriceX96, v3Factory);

        LpPosition[] memory positions = CoinDopplerMultiCurve.calculatePositions(isCoinToken0, poolConfiguration);

        // Initialize coin with pre-configured pool
        coin.initialize(payoutRecipient, owners, uri, name, symbol, platformReferrer, currency, poolAddress, poolConfiguration, positions);

        emit CoinCreated(
            msg.sender,
            payoutRecipient,
            platformReferrer,
            currency,
            uri,
            name,
            symbol,
            address(coin),
            poolAddress,
            IVersionedContract(address(coin)).contractVersion()
        );
    }

    function _setupV4Coin(
        ICoinV4 coin,
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
        PoolKey memory poolKey = CoinSetup.buildPoolKey(address(coin), currency, isCoinToken0, coin.hooks());

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

        (, address currency, uint160 sqrtPriceX96, bool isCoinToken0, PoolConfiguration memory poolConfiguration) = CoinSetup.generatePoolConfig(
            address(coin),
            poolConfig
        );

        if (CoinConfigurationVersions.isV3(version)) {
            _setupV3Coin(ICoinV3(coin), currency, isCoinToken0, sqrtPriceX96, poolConfiguration, payoutRecipient, owners, uri, name, symbol, platformReferrer);
        } else if (CoinConfigurationVersions.isV4(version)) {
            _setupV4Coin(ICoinV4(coin), currency, isCoinToken0, sqrtPriceX96, poolConfiguration, payoutRecipient, owners, uri, name, symbol, platformReferrer);
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

    /// @dev Generates a unique salt for deterministic deployment
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

    /// @dev Handles the first buy of a newly created coin
    /// @param coin The newly created coin contract
    /// @param orderSize The size of the first buy order; must match msg.value for ETH/WETH pairs
    function _handleFirstOrder(ICoin coin, uint256 orderSize) internal returns (uint256 coinsPurchased) {
        if (msg.value > 0 || orderSize > 0) {
            address currency = coin.currency();
            address payoutRecipient = coin.payoutRecipient();

            if (currency != Coin(payable(address(coin))).WETH()) {
                if (msg.value != 0) {
                    revert EthTransferInvalid();
                }

                _handleIncomingCurrency(currency, orderSize);

                IERC20(currency).approve(address(coin), orderSize);

                (, coinsPurchased) = Coin(payable(address(coin))).buy(payoutRecipient, orderSize, 0, 0, address(0));
            } else {
                (, coinsPurchased) = Coin(payable(address(coin))).buy{value: msg.value}(payoutRecipient, orderSize, 0, 0, address(0));
            }
        }
    }

    /// @dev Safely transfers ERC20 tokens from the caller to this contract to be sent to the newly created coin
    /// @param currency The ERC20 token address to transfer
    /// @param orderSize The amount of tokens to transfer for the order
    function _handleIncomingCurrency(address currency, uint256 orderSize) internal {
        uint256 beforeBalance = IERC20(currency).balanceOf(address(this));
        IERC20(currency).safeTransferFrom(msg.sender, address(this), orderSize);
        uint256 afterBalance = IERC20(currency).balanceOf(address(this));

        if ((afterBalance - beforeBalance) != orderSize) {
            revert ERC20TransferAmountMismatch();
        }
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
            if (!_equals(name, contractName())) {
                revert UpgradeToMismatchedContractName(contractName(), name);
            }
        } catch {}
    }

    function _equals(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(bytes(a)) == keccak256(bytes(b)));
    }
}
