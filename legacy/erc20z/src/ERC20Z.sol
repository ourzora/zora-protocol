// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Z} from "./interfaces/IERC20Z.sol";
import {IWETH} from "@zoralabs/shared-contracts/interfaces/IWETH.sol";
import {INonfungiblePositionManager} from "@zoralabs/shared-contracts/interfaces/uniswap/INonfungiblePositionManager.sol";
import {UniswapV3LiquidityCalculator} from "./uniswap/UniswapV3LiquidityCalculator.sol";
import {IRoyalties} from "./interfaces/IRoyalties.sol";
import {IZora1155} from "./interfaces/IZora1155.sol";
import {ERC20ZStorageDataLocation} from "./storage/ERC20ZStorageDataLocation.sol";

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

/// @title ERC20Z
/// @notice An extension of the ERC20 standard that integrates Zora's metadata functions.
/// @author @isabellasmallcombe @kulkarohan
contract ERC20Z is ReentrancyGuardUpgradeable, ERC20Upgradeable, ERC721Holder, ERC1155Holder, IERC20Z, ERC20ZStorageDataLocation {
    address internal constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    uint256 internal constant ONE_ERC_20 = 1e18;

    IWETH public immutable WETH;
    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    IRoyalties public immutable royalties;

    /// @notice The constructor for the ERC20Z contract
    /// @param _royalties The royalties contract address
    constructor(IRoyalties _royalties) initializer {
        royalties = _royalties;
        WETH = royalties.WETH();
        nonfungiblePositionManager = royalties.nonfungiblePositionManager();
    }

    /// @notice Initializes the creation of an ERC20z token and Uniswap V3 pool between the ERC20z and WETH.
    /// @param collection The 1155 collection address
    /// @param tokenId The 1155 token ID
    /// @param name The ERC20z token name
    /// @param symbol The ERC20z token symbol
    function initialize(address collection, uint256 tokenId, string calldata name, string calldata symbol) external initializer returns (address) {
        __ERC20_init(name, symbol);

        ERC20ZStorage storage erc20zStorage = _getERC20ZStorage();

        erc20zStorage.saleStrategy = msg.sender;
        erc20zStorage.collection = collection;
        erc20zStorage.tokenId = tokenId;

        address token0 = address(WETH) < address(this) ? address(WETH) : address(this);
        address token1 = address(WETH) < address(this) ? address(this) : address(WETH);
        uint160 sqrtPriceX96 = token0 == address(WETH)
            ? UniswapV3LiquidityCalculator.SQRT_PRICE_X96_WETH_0
            : UniswapV3LiquidityCalculator.SQRT_PRICE_X96_ERC20Z_0;

        address pool = nonfungiblePositionManager.createAndInitializePoolIfNecessary(token0, token1, UniswapV3LiquidityCalculator.FEE, sqrtPriceX96);

        erc20zStorage.pool = pool;

        return pool;
    }

    /// @notice Returns the underlying Zora ERC1155 collection, token id, and creator
    function tokenInfo() public view returns (TokenInfo memory) {
        ERC20ZStorage storage erc20zStorage = _getERC20ZStorage();

        return
            TokenInfo({
                collection: erc20zStorage.collection,
                tokenId: erc20zStorage.tokenId,
                creator: IZora1155(erc20zStorage.collection).getCreatorRewardRecipient(erc20zStorage.tokenId)
            });
    }

    /// @notice Returns the Uniswap V3 pool address and initial liquidity position id
    function tokenLiquidityInfo() public view returns (address pool, uint256 initialLiquidityPositionId) {
        ERC20ZStorage storage erc20zStorage = _getERC20ZStorage();

        pool = erc20zStorage.pool;
        initialLiquidityPositionId = erc20zStorage.initialLiquidityPoolPositionId;
    }

    /// @notice Returns the ERC20Z token URI
    function tokenURI() public view returns (string memory) {
        return _contractURI();
    }

    /// @notice Returns the ERC20Z contract URI
    function contractURI() public view returns (string memory) {
        return _contractURI();
    }

    /// @notice Returns the ERC20Z URI
    function _contractURI() internal view returns (string memory) {
        ERC20ZStorage storage erc20zStorage = _getERC20ZStorage();

        return IZora1155(erc20zStorage.collection).uri(erc20zStorage.tokenId);
    }

    /// @notice Called by the ZoraTimedSaleStrategy contract upon the completion of a primary sale.
    ///         This function handles the creation of ERC20 tokens and a Uniswap V3 liquidity pool.
    /// @param erc20TotalSupply The total supply of the ERC20z token
    /// @param erc20Reserve The reserve amount of the ERC20z token
    /// @param erc20Liquidity The liquidity amount of the ERC20z token
    /// @param erc20Excess The excess amount of the ERC20z token
    /// @param erc1155Excess The excess amount of the ERC1155 token
    function activate(
        uint256 erc20TotalSupply,
        uint256 erc20Reserve,
        uint256 erc20Liquidity,
        uint256 erc20Excess,
        uint256 erc1155Excess
    ) external nonReentrant {
        ERC20ZStorage storage erc20zStorage = _getERC20ZStorage();

        if (msg.sender != erc20zStorage.saleStrategy) {
            revert OnlySaleStrategy();
        }

        if (erc20TotalSupply != (erc20Reserve + erc20Liquidity + erc20Excess)) {
            revert InvalidParams();
        }

        if (erc20zStorage.initialLiquidityPoolPositionId > 0) {
            revert AlreadyActivatedCannotReactivate();
        }

        _mint(address(this), erc20TotalSupply);

        uint256 ethLiquidity = address(this).balance;

        WETH.deposit{value: ethLiquidity}();

        SafeERC20.safeIncreaseAllowance(IERC20(address(WETH)), address(nonfungiblePositionManager), ethLiquidity);
        SafeERC20.safeIncreaseAllowance(this, address(nonfungiblePositionManager), erc20Liquidity);

        (address token0, address token1, uint256 amount0, uint256 amount1 /*uint128 liquidity*/, ) = UniswapV3LiquidityCalculator.calculateLiquidityAmounts(
            address(WETH),
            ethLiquidity,
            address(this),
            erc20Liquidity
        );

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: UniswapV3LiquidityCalculator.FEE,
            tickLower: UniswapV3LiquidityCalculator.TICK_LOWER,
            tickUpper: UniswapV3LiquidityCalculator.TICK_UPPER,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 positionId, uint256 lpLiquidity /*uint256 lpAmount0*/ /*uint256 lpAmount1*/, , ) = nonfungiblePositionManager.mint(params);

        erc20zStorage.initialLiquidityPoolPositionId = positionId;

        // Transfer position from this address to the royalties address
        nonfungiblePositionManager.safeTransferFrom(address(this), address(royalties), positionId, "");

        emit SecondaryMarketActivated({
            token0: token0,
            amount0: amount0,
            token1: token1,
            amount1: amount1,
            fee: UniswapV3LiquidityCalculator.FEE,
            positionId: positionId,
            lpLiquidity: lpLiquidity,
            erc20Excess: erc20Excess,
            erc1155Excess: erc1155Excess
        });

        if (erc20Excess > 0) {
            SafeERC20.safeTransfer(this, DEAD_ADDRESS, erc20Excess);
        }

        if (erc1155Excess > 0) {
            IERC1155(erc20zStorage.collection).safeTransferFrom(address(this), DEAD_ADDRESS, erc20zStorage.tokenId, erc1155Excess, "");
        }
    }

    /// @notice Wraps tokens from ERC1155 to ERC20z
    /// @param amount1155 The amount of 1155 tokens to wrap
    /// @param recipient The recipient address
    function wrap(uint256 amount1155, address recipient) external {
        ERC20ZStorage storage erc20zStorage = _getERC20ZStorage();

        IERC1155(erc20zStorage.collection).safeTransferFrom(msg.sender, address(this), erc20zStorage.tokenId, amount1155, abi.encode(recipient));
    }

    /// @notice Unwraps tokens from ERC20z to ERC1155
    /// @param amount20z Amount of ERC20z tokens to unwrap
    /// @param recipient Recipient address
    function unwrap(uint256 amount20z, address recipient) external {
        if (totalSupply() == 0) {
            revert SecondaryMarketHasNotYetStarted();
        }

        if (recipient == address(0)) {
            revert RecipientAddressZero();
        }

        if (amount20z % ONE_ERC_20 != 0) {
            revert InvalidAmount20z();
        }

        uint256 amount1155 = amount20z / ONE_ERC_20;

        ERC20ZStorage storage erc20zStorage = _getERC20ZStorage();

        emit ConvertedTo1155(address(this), amount20z, erc20zStorage.collection, erc20zStorage.tokenId, amount1155, recipient);

        SafeERC20.safeTransferFrom(this, msg.sender, address(this), amount20z);

        IERC1155(erc20zStorage.collection).safeTransferFrom(address(this), recipient, erc20zStorage.tokenId, amount1155, "");
    }

    /// @notice Receive ETH from the ZoraTimedSaleStrategy contract
    receive() external payable {
        if (msg.sender != _getERC20ZStorage().saleStrategy) {
            revert OnlySaleStrategy();
        }
    }

    /// @notice Handles receiving Uniswap LP NFTs
    /// @param from The address which previously owned the token
    /// @param operator The address which initiated the transfer
    /// @param tokenId The ERC721 token id
    /// @param data Additional data with no specified format
    function onERC721Received(address from, address operator, uint256 tokenId, bytes memory data) public virtual override returns (bytes4) {
        if (msg.sender != _getERC20ZStorage().pool) {
            revert OnlySupportReceivingERC721UniswapPoolNFTs();
        }

        return super.onERC721Received(from, operator, tokenId, data);
    }

    /// @notice Handles receiving single ERC1155 NFTs.
    ///         Called at the end of a `safeTransferFrom` after the balance has been updated.
    /// @param operator The address which initiated the transfer (i.e. msg.sender)
    /// @param from The address which previously owned the token
    /// @param id The ID of the token being transferred
    /// @param value The amount of tokens being transferred
    /// @param data Additional data with no specified format
    /// @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes memory data) public virtual override returns (bytes4) {
        _requireSending1155AsZoraNFT();

        _erc1155TokenReceived(operator, from, id, value, data);

        return super.onERC1155Received(operator, from, id, value, data);
    }

    /// @notice Handles the receiving the underlying ERC1155 token as a batch transfer.
    /// @param operator The address which initiated the batch transfer (i.e. msg.sender)
    /// @param from The address which previously owned the token
    /// @param ids An array containing ids of each token being transferred (order and length must match values array)
    /// @param values An array containing amounts of each token being transferred (order and length must match ids array)
    /// @param data Additional data with no specified format
    /// @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` if transfer is allowed
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) public virtual override returns (bytes4) {
        _requireSending1155AsZoraNFT();

        if (ids.length != values.length) {
            revert IDsDoNotMatchValuesLength();
        }

        for (uint256 i = 0; i < ids.length; i++) {
            _erc1155TokenReceived(operator, from, ids[i], values[i], data);
        }

        return super.onERC1155BatchReceived(operator, from, ids, values, data);
    }

    /// @notice Handles ERC1155 receive validation, conversion to ERC20z, and transfers
    /// @param operator The address which initiated the transfer
    /// @param nftFrom The address which previously owned the token
    /// @param tokenId The token id being transferred
    /// @param amount1155 The amount of tokens being transferred
    /// @param data Additional data with no specified format
    function _erc1155TokenReceived(address operator, address nftFrom, uint256 tokenId, uint256 amount1155, bytes memory data) internal {
        ERC20ZStorage storage erc20zStorage = _getERC20ZStorage();

        if (tokenId != erc20zStorage.tokenId) {
            revert TokenIdNotValidToSwap();
        }

        if (operator == erc20zStorage.saleStrategy && nftFrom == address(0)) {
            // Ignore admin-minted NFTs
            emit ReceivedAdminMintNFTs(amount1155);
            return;
        }

        if (totalSupply() == 0) {
            revert SecondaryMarketHasNotYetStarted();
        }

        address recipient = nftFrom;
        if (data.length > 0) {
            (recipient) = abi.decode(data, (address));
        }

        if (recipient == address(0)) {
            revert RecipientAddressZero();
        }

        // Convert the ERC1155 amount to ERC20 amount
        uint256 amount20z = amount1155 * ONE_ERC_20;

        SafeERC20.safeTransfer(this, recipient, amount20z);

        emit ConvertedTo20z(address(this), amount20z, erc20zStorage.collection, erc20zStorage.tokenId, amount1155, recipient);
    }

    /// @notice Requires the caller to be the underlying ERC1555 collection
    function _requireSending1155AsZoraNFT() internal view {
        if (msg.sender != address(_getERC20ZStorage().collection)) {
            revert OnlySupportReceivingERC1155AssociatedZoraNFT();
        }
    }
}
