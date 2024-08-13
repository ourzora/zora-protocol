// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IProtocolRewards} from "@zoralabs/protocol-rewards/src/interfaces/IProtocolRewards.sol";
import {IReduceSupply} from "@zoralabs/shared-contracts/interfaces/IReduceSupply.sol";
import {IZoraTimedSaleStrategy} from "../interfaces/IZoraTimedSaleStrategy.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {ICreatorCommands} from "../interfaces/ICreatorCommands.sol";
import {IERC20Z} from "../interfaces/IERC20Z.sol";
import {IZora1155} from "../interfaces/IZora1155.sol";
import {ZoraTimedSaleStrategyConstants} from "./ZoraTimedSaleStrategyConstants.sol";
import {ZoraTimedSaleStorageDataLocation} from "../storage/ZoraTimedSaleStorageDataLocation.sol";
import {IUniswapV3SwapCallback} from "../interfaces/uniswap/IUniswapV3SwapCallback.sol";
import {UniswapV3LiquidityCalculator} from "../uniswap/UniswapV3LiquidityCalculator.sol";
import {IUniswapV3Pool} from "../interfaces/uniswap/IUniswapV3Pool.sol";

/*


             ░░░░░░░░░░░░░░              
        ░░▒▒░░░░░░░░░░░░░░░░░░░░        
      ░░▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░      
    ░░▒▒▒▒░░░░░░░░░░░░░░    ░░░░░░░░    
   ░▓▓▒▒▒▒░░░░░░░░░░░░        ░░░░░░░    
  ░▓▓▓▒▒▒▒░░░░░░░░░░░░        ░░░░░░░░  
  ░▓▓▓▒▒▒▒░░░░░░░░░░░░░░    ░░░░░░░░░░  
  ░▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░░  
  ░▓▓▓▓▓▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░░░░  
   ░▓▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░░░░  
    ░░▓▓▓▓▒▒▒▒▒▒░░░░░░░░░░░░░░░░░░░░    
    ░░▓▓▓▓▓▓▒▒▒▒▒▒▒▒░░░░░░░░░▒▒▒▒▒░░    
      ░░▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒░░      
          ░░▓▓▓▓▓▓▓▓▓▓▓▓▒▒░░░          

               OURS TRULY,


*/

/// @title Zora Timed Sale Strategy Impl
/// @notice A timed sale strategy for Zora 1155 tokens
/// @author @isabellasmallcombe @kulkarohan
contract ZoraTimedSaleStrategyImpl is
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    IMinter1155,
    IZoraTimedSaleStrategy,
    ZoraTimedSaleStorageDataLocation,
    ZoraTimedSaleStrategyConstants,
    IUniswapV3SwapCallback
{
    IProtocolRewards public protocolRewards;
    address public erc20zImpl;

    /// @notice Constructor for the Zora Timed Sale Strategy
    constructor() initializer {}

    /// @notice Initializes the Zora Timed Sale Strategy
    /// @param _defaultOwner The default owner of the contract
    /// @param _zoraRewardRecipient The address to receive the Zora rewards
    /// @param _erc20zImpl The address of the ERC20Z implementation
    function initialize(address _defaultOwner, address _zoraRewardRecipient, address _erc20zImpl, IProtocolRewards _protocolRewards) external initializer {
        _requireNotAddressZero(_defaultOwner);
        _requireNotAddressZero(_zoraRewardRecipient);
        _requireNotAddressZero(_erc20zImpl);
        _requireNotAddressZero(address(_protocolRewards));

        erc20zImpl = _erc20zImpl;
        protocolRewards = _protocolRewards;

        __ReentrancyGuard_init();
        __Ownable_init(_defaultOwner);
        __UUPSUpgradeable_init();

        _getZoraTimedSaleStrategyStorage().zoraRewardRecipient = _zoraRewardRecipient;
    }

    /// @notice Called by an 1155 collection to set the sale config for a given token
    /// @dev Additionally creates an ERC20Z and Uniswap V3 pool for the token
    /// @param tokenId The collection token id to set the sale config for
    /// @param salesConfig The sale config to set
    function setSale(uint256 tokenId, SalesConfig calldata salesConfig) external {
        address collection = msg.sender;

        if (!IZora1155(collection).supportsInterface(type(IReduceSupply).interfaceId)) {
            revert ZoraCreator1155ContractNeedsToSupportReduceSupply();
        }

        if (salesConfig.saleEnd <= block.timestamp) {
            revert EndTimeCannotBeInThePast();
        }

        if (salesConfig.saleStart >= salesConfig.saleEnd) {
            revert StartTimeCannotBeAfterEndTime();
        }

        SaleStorage storage saleStorage = _getZoraTimedSaleStrategyStorage().sales[collection][tokenId];

        if (saleStorage.erc20zAddress != address(0)) {
            revert SaleAlreadySet();
        }

        bytes32 salt = _generateSalt(collection, tokenId);

        address erc20zAddress = Clones.cloneDeterministic(erc20zImpl, salt);

        address poolAddress = IERC20Z(erc20zAddress).initialize(collection, tokenId, salesConfig.name, salesConfig.symbol);

        saleStorage.erc20zAddress = payable(erc20zAddress);
        saleStorage.saleStart = salesConfig.saleStart;
        saleStorage.poolAddress = poolAddress;
        saleStorage.saleEnd = salesConfig.saleEnd;

        emit SaleSet(collection, tokenId, salesConfig, erc20zAddress, poolAddress, MINT_PRICE);
    }

    /// @notice Called by an 1155 collection to update the sale time if the sale has not started or ended.
    /// @param tokenId The 1155 token id
    /// @param newStartTime The new start time for the sale, ignored if the existing sale has already started
    /// @param newEndTime The new end time for the sale
    function updateSale(uint256 tokenId, uint64 newStartTime, uint64 newEndTime) external {
        SaleStorage storage saleStorage = _getZoraTimedSaleStrategyStorage().sales[msg.sender][tokenId];

        // Ensure the sale has been set
        if (saleStorage.erc20zAddress == address(0)) {
            revert SaleNotSet();
        }

        // Ensure the existing sale has not ended.
        if (saleStorage.secondaryActivated || block.timestamp >= saleStorage.saleEnd) {
            revert SaleEnded();
        }

        // If the existing sale is already in progress, only the end time can be updated.
        if (block.timestamp >= saleStorage.saleStart) {
            // Ensure the new end time is in the future.
            if (newEndTime <= block.timestamp) {
                revert EndTimeCannotBeInThePast();
            }

            saleStorage.saleEnd = newEndTime;

            // Otherwise the sale has not started and both the start and end times can be updated.
        } else {
            // Ensure the new start time is before the new end time
            if (newStartTime >= newEndTime) {
                revert StartTimeCannotBeAfterEndTime();
            }

            saleStorage.saleStart = newStartTime;
            saleStorage.saleEnd = newEndTime;
        }

        SalesConfig memory saleConfig = SalesConfig({
            saleStart: saleStorage.saleStart,
            saleEnd: saleStorage.saleEnd,
            name: IERC20Z(saleStorage.erc20zAddress).name(),
            symbol: IERC20Z(saleStorage.erc20zAddress).symbol()
        });

        emit SaleSet(msg.sender, tokenId, saleConfig, saleStorage.erc20zAddress, saleStorage.poolAddress, MINT_PRICE);
    }

    /// @notice Called by a collector to mint a token
    /// @param mintTo The address to mint the token to
    /// @param quantity The quantity of tokens to mint
    /// @param collection The address of the 1155 token to mint
    /// @param tokenId The ID of the token to mint
    /// @param mintReferral The address of the mint referral
    /// @param comment The optional mint comment
    function mint(
        address mintTo,
        uint256 quantity,
        address collection,
        uint256 tokenId,
        address mintReferral,
        string calldata comment
    ) external payable nonReentrant {
        SaleStorage storage saleStorage = _getZoraTimedSaleStrategyStorage().sales[collection][tokenId];

        if (saleStorage.erc20zAddress == address(0)) {
            revert SaleNotSet();
        }

        if (msg.value != (MINT_PRICE * quantity)) {
            revert WrongValueSent();
        }

        if (block.timestamp < saleStorage.saleStart) {
            revert SaleHasNotStarted();
        }

        if (block.timestamp > saleStorage.saleEnd) {
            revert SaleEnded();
        }

        IZora1155(collection).adminMint(mintTo, tokenId, quantity, "");

        _distributeRewards(tokenId, collection, mintReferral, quantity);

        if (bytes(comment).length > 0) {
            emit MintComment(mintTo, collection, tokenId, quantity, comment);
        }
    }

    /// @notice Calculate the ERC20z activation values
    /// @param collection The collection address
    /// @param tokenId The token ID
    /// @param erc20zAddress The ERC20Z address
    function calculateERC20zActivate(address collection, uint256 tokenId, address erc20zAddress) public view returns (ERC20zActivate memory) {
        // Get the current total supply of the ERC1155 token
        uint256 current1155Supply = IZora1155(collection).getTokenInfo(tokenId).totalMinted;

        // Calculate the ERC20 reserve based on the ERC1155 supply
        uint256 erc20Reserve = current1155Supply * ONE_ERC_20;

        // Calculate the ERC20 liquidity based on the total ETH from the market reward of each mint and the starting price of the liquidity pool
        uint256 erc20Liquidity = (erc20zAddress.balance * ONE_ERC_20) / MINT_PRICE;

        // Calculate the minimum ERC20 tokens needed for reserve and liquidity
        uint256 minERC20Needed = erc20Reserve + erc20Liquidity;

        // Calculate the final ERC1155 supply, rounding up to the nearest whole token
        uint256 final1155Supply = (minERC20Needed + ONE_ERC_20 - 1) / ONE_ERC_20;

        // Calculate how many additional ERC1155 tokens need to be minted
        uint256 additionalERC1155ToMint = final1155Supply - current1155Supply;

        // Calculate the final total ERC20Z supply
        // Divide before multiply is necessary here to round up to the nearest erc20 supply to match the 1155 supply
        // slither-disable-next-line divide-before-multiply
        uint256 finalTotalERC20ZSupply = final1155Supply * ONE_ERC_20;

        // Calculate any excess ERC1155 tokens
        uint256 excessERC1155 = final1155Supply - (minERC20Needed / ONE_ERC_20);

        // Calculate any excess ERC20 tokens
        uint256 excessERC20 = finalTotalERC20ZSupply - minERC20Needed;

        return ERC20zActivate(finalTotalERC20ZSupply, erc20Reserve, erc20Liquidity, excessERC20, excessERC1155, additionalERC1155ToMint, final1155Supply);
    }

    /// @notice Called by anyone upon the end of a primary sale to launch the secondary market.
    /// @param collection The 1155 collection address
    /// @param tokenId The 1155 token id
    function launchMarket(address collection, uint256 tokenId) external {
        SaleStorage storage saleStorage = _getZoraTimedSaleStrategyStorage().sales[collection][tokenId];

        // Ensure the sale has ended
        if (block.timestamp < saleStorage.saleEnd) {
            revert SaleInProgress();
        }

        // Ensure the market hasn't already been launched
        if (saleStorage.secondaryActivated) {
            revert MarketAlreadyLaunched();
        }

        saleStorage.secondaryActivated = true;

        address erc20zAddress = saleStorage.erc20zAddress;

        if (erc20zAddress.balance == 0) {
            revert NeedsToBeAtLeastOneSaleToStartMarket();
        }

        ERC20zActivate memory calculatedValues = calculateERC20zActivate(collection, tokenId, erc20zAddress);

        emit MarketLaunched(collection, tokenId, erc20zAddress, saleStorage.poolAddress);

        // Cap the ERC1155 token supply to the final calculated amount
        IZora1155(collection).reduceSupply(tokenId, calculatedValues.final1155Supply);

        // Mint additional ERC1155 tokens if needed
        IZora1155(collection).adminMint(erc20zAddress, tokenId, calculatedValues.additionalERC1155ToMint, "");

        // Desired initial price
        bool tokenIsFirst = IUniswapV3Pool(saleStorage.poolAddress).token0() == saleStorage.erc20zAddress;
        uint160 desiredSqrtPriceX96 = tokenIsFirst ? UniswapV3LiquidityCalculator.SQRT_PRICE_X96_ERC20Z_0 : UniswapV3LiquidityCalculator.SQRT_PRICE_X96_WETH_0;

        if (IUniswapV3Pool(saleStorage.poolAddress).slot0().sqrtPriceX96 != desiredSqrtPriceX96) {
            IUniswapV3Pool(saleStorage.poolAddress).swap(address(this), tokenIsFirst, 1, desiredSqrtPriceX96, "");
        }

        // Activate the secondary market on Uniswap via the ERC20Z contract
        IERC20Z(erc20zAddress).activate({
            erc20TotalSupply: calculatedValues.finalTotalERC20ZSupply,
            erc20Reserve: calculatedValues.erc20Reserve,
            erc20Liquidity: calculatedValues.erc20Liquidity,
            erc20Excess: calculatedValues.excessERC20,
            erc1155Excess: calculatedValues.excessERC1155
        });
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external {
        // no-op to pass through for force-setting the price
    }

    /// @notice Computes the rewards for a given quantity of tokens
    /// @param quantity The quantity of tokens to compute rewards for
    function computeRewards(uint256 quantity) public pure returns (RewardsSettings memory) {
        return
            RewardsSettings({
                totalReward: MINT_PRICE * quantity,
                creatorReward: CREATOR_REWARD * quantity,
                createReferralReward: CREATOR_REFERRER_REWARD * quantity,
                mintReferralReward: MINT_REFERRER_REWARD * quantity,
                marketReward: MARKET_REWARD * quantity,
                zoraReward: ZORA_REWARD * quantity
            });
    }

    /// @notice Gets the create referral address for a given token
    /// @param collection The address of the token contract
    /// @param tokenId The ID of the token
    function getCreateReferral(address collection, uint256 tokenId) public view returns (address createReferral) {
        try IZora1155(collection).createReferrals(tokenId) returns (address contractCreateReferral) {
            createReferral = contractCreateReferral;
        } catch {}

        if (createReferral == address(0)) {
            createReferral = _getZoraTimedSaleStrategyStorage().zoraRewardRecipient;
        }
    }

    /// @notice Distributes the rewards to the appropriate addresses
    /// @param tokenId The ID of the token to mint
    /// @param collection The address of the 1155 token to mint
    /// @param mintReferral The address of the mint referral
    /// @param quantity The quantity of tokens to mint
    function _distributeRewards(uint256 tokenId, address collection, address mintReferral, uint256 quantity) private {
        address creator = IZora1155(collection).getCreatorRewardRecipient(tokenId);
        address createReferral = getCreateReferral(collection, tokenId);

        address zora = _getZoraTimedSaleStrategyStorage().zoraRewardRecipient;
        address erc20zAddress = _getZoraTimedSaleStrategyStorage().sales[collection][tokenId].erc20zAddress;

        if (mintReferral == address(0)) {
            mintReferral = zora;
        }

        RewardsSettings memory rewards = computeRewards(quantity);

        // slither-disable-next-line arbitrary-send-eth
        protocolRewards.depositRewards{value: rewards.totalReward - rewards.marketReward}(
            creator,
            rewards.creatorReward,
            createReferral,
            rewards.createReferralReward,
            mintReferral,
            rewards.mintReferralReward,
            address(0),
            0,
            zora,
            rewards.zoraReward
        );

        Address.sendValue(payable(erc20zAddress), rewards.marketReward);

        emit ZoraTimedSaleStrategyRewards(
            collection,
            tokenId,
            creator,
            rewards.creatorReward,
            createReferral,
            rewards.createReferralReward,
            mintReferral,
            rewards.mintReferralReward,
            erc20zAddress,
            rewards.marketReward,
            zora,
            rewards.zoraReward
        );
    }

    /// @notice Generates a salt for the deployment of the ERC20Z
    /// @param collection The collection address
    /// @param tokenId The token ID
    function _generateSalt(address collection, uint256 tokenId) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(collection, tokenId, msg.sender, block.number, block.prevrandao, block.timestamp, tx.gasprice));
    }

    /// @notice Reverts if the address is address(0)
    /// @param _address The address to check
    function _requireNotAddressZero(address _address) internal pure {
        if (_address == address(0)) {
            revert AddressZero();
        }
    }

    /// @dev This sale strategy does not support minting via the requestMint function
    function requestMint(address, uint256, uint256, uint256, bytes calldata) external pure returns (ICreatorCommands.CommandSet memory) {
        revert RequestMintInvalidUseMint();
    }

    /// @notice Returns the sale config for a given token
    /// @param collection The 1155 collection address
    /// @param tokenId The 1155 token id
    function sale(address collection, uint256 tokenId) external view returns (SaleStorage memory) {
        return _getZoraTimedSaleStrategyStorage().sales[collection][tokenId];
    }

    /// @notice IERC165 interface support
    /// @param interfaceId The interface ID to check
    function supportsInterface(bytes4 interfaceId) public pure virtual returns (bool) {
        // Interface id 0x6890e5b3 is hardcoded due to header incompat but it's used by the 1155 contract to check for requestMint support.
        return interfaceId == type(IMinter1155).interfaceId || interfaceId == 0x6890e5b3 || interfaceId == type(IERC165).interfaceId;
    }

    /// @notice The name of the contract
    function contractName() external pure returns (string memory) {
        return "Zora Timed Sale Strategy";
    }

    /// @notice The URI of the contract
    function contractURI() external pure returns (string memory) {
        return "https://github.com/ourzora/zora-protocol/";
    }

    /// @notice The version of the contract
    function contractVersion() external pure returns (string memory) {
        return "1.1.0";
    }

    /// @notice Update the Zora reward recipient
    /// @param recipient new recipient address to set
    function setZoraRewardRecipient(address recipient) external onlyOwner {
        _requireNotAddressZero(recipient);

        ZoraTimedSaleStrategyStorage storage saleStrategyStorage = _getZoraTimedSaleStrategyStorage();

        emit ZoraRewardRecipientUpdated(saleStrategyStorage.zoraRewardRecipient, recipient);

        saleStrategyStorage.zoraRewardRecipient = recipient;
    }

    /// @notice Update the contract implementation
    /// @param newImpl the new implementation address
    function _authorizeUpgrade(address newImpl) internal override onlyOwner {}
}
