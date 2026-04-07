// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IWETH} from "@zoralabs/shared-contracts/interfaces/IWETH.sol";
import {INonfungiblePositionManager} from "@zoralabs/shared-contracts/interfaces/uniswap/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "@zoralabs/shared-contracts/interfaces/uniswap/IUniswapV3Pool.sol";
import {IERC20Z} from "../interfaces/IERC20Z.sol";
import {IZora1155} from "../interfaces/IZora1155.sol";
import {IRoyalties} from "../interfaces/IRoyalties.sol";

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

/// @title Royalties
/// @notice Manages the royalty distribution for Zora 1155 secondary markets on Uniswap V3
/// @author @isabellasmallcombe @kulkarohan
contract Royalties is IRoyalties, ReentrancyGuard, ERC721Holder {
    using SafeERC20 for IERC20;

    IWETH public WETH;
    INonfungiblePositionManager public nonfungiblePositionManager;
    address payable public feeRecipient;
    uint256 public feeBps;

    mapping(address erc20z => uint256 positionId) public positionsByErc20z;

    /// @notice Initializes the Royalties contract with chain-specific addresses
    /// @param _weth The WETH address
    /// @param _nonfungiblePositionManager The Uniswap V3 nonfungible position manager address
    /// @param _feeRecipient The fee recipient address
    /// @param _feeBps The fee basis points
    function initialize(IWETH _weth, INonfungiblePositionManager _nonfungiblePositionManager, address payable _feeRecipient, uint256 _feeBps) external {
        if (address(WETH) != address(0)) {
            revert AlreadyInitialized();
        }

        _requireNotAddressZero(address(_weth));
        _requireNotAddressZero(address(_nonfungiblePositionManager));
        _requireNotAddressZero(_feeRecipient);

        WETH = _weth;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;
    }

    /// @notice Claim royalties for a creator
    /// @param erc20z ERC20Z address to claim royalties from
    /// @param recipient The recipient address
    function claim(address erc20z, address payable recipient) external nonReentrant {
        _requireNotAddressZero(recipient);

        (address payable creator, uint256 positionId, IERC20Z.TokenInfo memory tokenInfo) = _getInfoForERC20Z(erc20z);

        if (msg.sender != creator) {
            revert OnlyCreatorCanCall();
        }

        _claim(tokenInfo, positionId, creator, recipient);
    }

    /// @notice Claim royalties for a creator
    /// @param erc20z ERC20Z address to claim royalties from
    function claimFor(address erc20z) external nonReentrant {
        (address payable creator, uint256 positionId, IERC20Z.TokenInfo memory tokenInfo) = _getInfoForERC20Z(erc20z);

        _claim(tokenInfo, positionId, creator, creator);
    }

    /// @notice Get information for a given erc20z token
    /// @param erc20z erc20z token contract address to get information for
    function _getInfoForERC20Z(address erc20z) internal view returns (address payable creator, uint256 positionId, IERC20Z.TokenInfo memory tokenInfo) {
        positionId = positionsByErc20z[erc20z];

        tokenInfo = IERC20Z(erc20z).tokenInfo();

        creator = payable(IZora1155(tokenInfo.collection).getCreatorRewardRecipient(tokenInfo.tokenId));
        if (creator == address(0)) {
            revert CreatorMustBeSet();
        }
    }

    /// @notice Run the underlying claim function
    /// @param tokenInfo token information for the token to claim from
    /// @param positionId position id for the claim token
    /// @param creator creator for the token
    /// @param recipient recipient for the reward tokens
    function _claim(IERC20Z.TokenInfo memory tokenInfo, uint256 positionId, address creator, address payable recipient) internal {
        (address token0, address token1, uint256 amount0, uint256 amount1) = _collect(positionId);

        _transfer(token0, amount0, recipient);
        _transfer(token1, amount1, recipient);

        emit RoyaltyClaim({
            collection: tokenInfo.collection,
            tokenId: tokenInfo.tokenId,
            creator: creator,
            recipient: recipient,
            positionAddress: address(nonfungiblePositionManager),
            positionId: positionId,
            token0: token0 == address(WETH) ? address(0) : token0,
            token0Amount: amount0,
            token1: token1 == address(WETH) ? address(0) : token1,
            token1Amount: amount1
        });
    }

    /// @notice Collect Uniswap V3 LP position rewards
    /// @param positionId The Uniswap V3 position token id
    function _collect(uint256 positionId) internal returns (address token0, address token1, uint256 amount0, uint256 amount1) {
        (, , token0, token1, , , , , , , , ) = nonfungiblePositionManager.positions(positionId);

        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: positionId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);
    }

    /// @notice Transfer ERC20z or ETH to a recipient
    /// @param token The token address
    /// @param amount The token amount
    /// @param recipient The recipient address
    function _transfer(address token, uint256 amount, address payable recipient) internal {
        if (amount > 0) {
            uint256 fee = getFee(amount);
            uint256 amountRemaining = amount - fee;

            if (token == address(WETH)) {
                WETH.withdraw(amount);

                Address.sendValue(feeRecipient, fee);
                Address.sendValue(recipient, amountRemaining);
            } else {
                IERC20(token).safeTransfer(feeRecipient, fee);

                IERC20(token).safeTransfer(recipient, amountRemaining);
            }
        }
    }

    /// @notice Returns the total recipient fee based on a given amount
    /// @param amount the amount
    function getFee(uint256 amount) public view returns (uint256) {
        return (amount * feeBps) / 10_000;
    }

    /// @notice The total unclaimed fees for an ERC20z token
    /// @param erc20z The ERC20z address
    function getUnclaimedFees(address erc20z) public view returns (UnclaimedFees memory) {
        uint256 positionId = positionsByErc20z[erc20z];

        (
            ,
            ,
            address token0,
            address token1,
            ,
            ,
            ,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = nonfungiblePositionManager.positions(positionId);

        (address pool, ) = IERC20Z(erc20z).tokenLiquidityInfo();

        uint256 feeGrowthGlobal0 = IUniswapV3Pool(pool).feeGrowthGlobal0X128();
        uint256 feeGrowthGlobal1 = IUniswapV3Pool(pool).feeGrowthGlobal1X128();

        uint128 accruedFees0 = uint128(((feeGrowthGlobal0 - feeGrowthInside0LastX128) * liquidity) / 2 ** 128);
        uint128 accruedFees1 = uint128(((feeGrowthGlobal1 - feeGrowthInside1LastX128) * liquidity) / 2 ** 128);

        return UnclaimedFees({token0: token0, token1: token1, token0Amount: tokensOwed0 + accruedFees0, token1Amount: tokensOwed1 + accruedFees1});
    }

    /// @notice The total unclaimed fees for a batch of ERC20z tokens
    /// @param erc20z The ERC20z addresses
    function getUnclaimedFeesBatch(address[] calldata erc20z) external view returns (UnclaimedFees[] memory) {
        UnclaimedFees[] memory unclaimedFees = new UnclaimedFees[](erc20z.length);

        for (uint256 i; i < erc20z.length; ++i) {
            unclaimedFees[i] = getUnclaimedFees(erc20z[i]);
        }

        return unclaimedFees;
    }

    /// @notice Reverts if the address is address(0)
    /// @param _address The address to check
    function _requireNotAddressZero(address _address) internal pure {
        if (_address == address(0)) {
            revert AddressZero();
        }
    }

    /// @notice Receive ETH withdrawn from WETH
    receive() external payable {
        if (msg.sender != address(WETH)) {
            revert OnlyWeth();
        }
    }

    /// @notice Handles receiving a Uniswap V3 LP position
    /// @param operator The address which initiated the transfer
    /// @param from The address which previously owned the token
    /// @param positionId The ID of the Uniswap V3 position
    /// @param data Additional data with no specified format
    /// @return bytes4 The function selector to confirm the transfer was accepted
    function onERC721Received(address operator, address from, uint256 positionId, bytes memory data) public virtual override returns (bytes4) {
        if (msg.sender != address(nonfungiblePositionManager)) {
            revert ERC721SenderRoyaltiesNeedsToBePositionManager();
        }

        (, , address token0, address token1, , , , , , , , ) = nonfungiblePositionManager.positions(positionId);

        // If from token owner is not a part of the pair, revert.
        // This is not possible for WETH so we only check the ERC20Z part.
        if (from != token0 && from != token1) {
            revert OnlyErc20z();
        }

        positionsByErc20z[from] = positionId;

        emit RoyaltyDeposit({erc20zAddress: from, positionAddress: address(nonfungiblePositionManager), positionId: positionId});

        return super.onERC721Received(operator, from, positionId, data);
    }
}
