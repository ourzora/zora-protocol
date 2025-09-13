// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ICoin, IHasTotalSupplyForPositions, IHasCoinType} from "./interfaces/ICoin.sol";
import {IHasRewardsRecipients} from "./interfaces/IHasRewardsRecipients.sol";
import {ICoinComments} from "./interfaces/ICoinComments.sol";
import {IERC7572} from "./interfaces/IERC7572.sol";
import {IUniswapV3Factory} from "./interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IAirlock} from "./interfaces/IAirlock.sol";
import {IProtocolRewards} from "./interfaces/IProtocolRewards.sol";
import {IWETH} from "./interfaces/IWETH.sol";

import {IPoolManager, PoolKey, Currency, IHooks} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHasPoolKey, IHasSwapPath} from "./interfaces/ICoin.sol";
import {PoolConfiguration} from "./types/PoolConfiguration.sol";
import {UniV4SwapToCurrency} from "./libs/UniV4SwapToCurrency.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {IDeployedCoinVersionLookup} from "./interfaces/IDeployedCoinVersionLookup.sol";
import {IUpgradeableV4Hook} from "./interfaces/IUpgradeableV4Hook.sol";
import {CoinCommon} from "./libs/CoinCommon.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
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
abstract contract BaseCoin is ICoin, ContractVersionBase, ERC20PermitUpgradeable, MultiOwnable, ReentrancyGuardUpgradeable, ERC165Upgradeable {
    using SafeERC20 for IERC20;

    /// @notice The address of the protocol rewards contract
    address public immutable protocolRewards;
    /// @notice The address of the protocol reward recipient
    address public immutable protocolRewardRecipient;
    /// @notice The address of the Airlock contract, ownership is used for a protocol fee split.
    address public immutable airlock;

    /// @notice The Uniswap v4 pool manager singleton contract reference.
    IPoolManager public immutable poolManager;

    /// @notice The pool key for the coin. Type from Uniswap V4 core.
    PoolKey internal poolKey;

    /// @notice The configuration for the pool.
    PoolConfiguration internal poolConfiguration;

    /// @notice The metadata URI
    string public tokenURI;
    /// @notice The address of the coin creator
    address public payoutRecipient;
    /// @notice The address of the platform referrer
    address public platformReferrer;
    /// @notice The address of the currency
    address public currency;

    /// @notice The name of the token
    string private _name;
    /// @notice The symbol of the token
    string private _symbol;

    /**
     * @notice The constructor for the static Coin contract deployment shared across all Coins.
     * @param protocolRewardRecipient_ The address of the protocol reward recipient
     * @param protocolRewards_ The address of the protocol rewards contract
     * @param poolManager_ The address of the pool manager
     * @param airlock_ The address of the Airlock contract
     */
    constructor(address protocolRewardRecipient_, address protocolRewards_, IPoolManager poolManager_, address airlock_) initializer {
        if (protocolRewardRecipient_ == address(0)) {
            revert AddressZero();
        }
        if (protocolRewards_ == address(0)) {
            revert AddressZero();
        }
        if (address(poolManager_) == address(0)) {
            revert AddressZero();
        }
        if (airlock_ == address(0)) {
            revert AddressZero();
        }

        protocolRewardRecipient = protocolRewardRecipient_;
        protocolRewards = protocolRewards_;
        poolManager = poolManager_;
        airlock = airlock_;
    }

    /// @inheritdoc ICoin
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

        _initialize(payoutRecipient_, owners_, tokenURI_, name_, symbol_, platformReferrer_);

        // initialize the pool - the hook will mint its positions in the afterInitialize callback
        poolManager.initialize(poolKey, sqrtPriceX96);
    }

    /// @notice Initializes a new coin (internal version)
    /// @param payoutRecipient_ The address of the coin creator
    /// @param tokenURI_ The metadata URI
    /// @param name_ The coin name
    /// @param symbol_ The coin symbol
    /// @param platformReferrer_ The address of the platform referrer
    function _initialize(
        address payoutRecipient_,
        address[] memory owners_,
        string memory tokenURI_,
        string memory name_,
        string memory symbol_,
        address platformReferrer_
    ) internal {
        // Validate the creation parameters
        if (payoutRecipient_ == address(0)) {
            revert AddressZero();
        }

        _setNameAndSymbol(name_, symbol_);

        // Set base contract state, leave name and symbol empty to save space.
        __ERC20_init("", "");

        // Set permit support without name later overriding name to match contract name.
        __ERC20Permit_init("");

        __MultiOwnable_init(owners_);
        __ReentrancyGuard_init();

        // Set mutable state
        _setPayoutRecipient(payoutRecipient_);
        _setContractURI(tokenURI_);

        // Store the referrer or use the protocol reward recipient if not set
        platformReferrer = platformReferrer_ == address(0) ? protocolRewardRecipient : platformReferrer_;

        // Distribute the initial supply
        _handleInitialDistribution();
    }

    /// @dev The initial mint and distribution of the coin supply.
    function _handleInitialDistribution() internal virtual {
        // Mint the total supply to the coin contract
        _mint(address(this), CoinConstants.MAX_TOTAL_SUPPLY);

        // Distribute the creator launch reward to the payout recipient
        _transfer(address(this), payoutRecipient, CoinConstants.CREATOR_LAUNCH_REWARD);
    }

    /// @notice Returns the name of the token for EIP712 domain.
    /// @notice This can change when the user changes the "name" of the token.
    /// @dev Overrides the default implementation to align name getter with Permit support.
    function _EIP712Name() internal pure override returns (string memory) {
        return "Coin";
    }

    /// @notice Enables a user to burn their tokens
    /// @param amount The amount of tokens to burn
    function burn(uint256 amount) external {
        // This burn function sets the from as msg.sender, so having an unauthed call is safe.
        _burn(msg.sender, amount);
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

    /**
     * @dev Returns the name of the token.
     */
    function name() public view override returns (string memory) {
        return _name;
    }

    function setNameAndSymbol(string memory newName, string memory newSymbol) external onlyOwner {
        _setNameAndSymbol(newName, newSymbol);
    }

    function _setNameAndSymbol(string memory newName, string memory newSymbol) internal {
        if (bytes(newName).length == 0) {
            revert NameIsRequired();
        }
        _name = newName;
        _symbol = newSymbol;
        emit NameAndSymbolUpdated(msg.sender, newName, newSymbol);
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /// @notice ERC165 interface support
    /// @param interfaceId The interface ID to check
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165Upgradeable) returns (bool) {
        return
            super.supportsInterface(interfaceId) ||
            interfaceId == type(ICoin).interfaceId ||
            interfaceId == type(ICoinComments).interfaceId ||
            interfaceId == type(IERC7572).interfaceId ||
            interfaceId == type(IHasRewardsRecipients).interfaceId ||
            interfaceId == type(IHasPoolKey).interfaceId ||
            interfaceId == type(IHasCoinType).interfaceId ||
            interfaceId == type(IHasTotalSupplyForPositions).interfaceId ||
            interfaceId == type(IHasSwapPath).interfaceId;
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

    /// @notice Returns the address of the Doppler protocol fee recipient
    function dopplerFeeRecipient() public view returns (address) {
        return IAirlock(airlock).owner();
    }

    /// @inheritdoc IHasPoolKey
    function getPoolKey() public view returns (PoolKey memory) {
        return poolKey;
    }

    /// @inheritdoc ICoin
    function getPoolConfiguration() public view returns (PoolConfiguration memory) {
        return poolConfiguration;
    }

    /// @inheritdoc ICoin
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
