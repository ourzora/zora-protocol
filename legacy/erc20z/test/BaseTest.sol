// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {IProtocolRewards} from "@zoralabs/shared-contracts/interfaces/IProtocolRewards.sol";
import {IWETH} from "@zoralabs/shared-contracts/interfaces/IWETH.sol";
import {INonfungiblePositionManager} from "@zoralabs/shared-contracts/interfaces/uniswap/INonfungiblePositionManager.sol";
import {ISwapRouter} from "@zoralabs/shared-contracts/interfaces/uniswap/ISwapRouter.sol";
import {IERC20Z} from "../src/interfaces/IERC20Z.sol";
import {ERC20Z} from "../src/ERC20Z.sol";
import {IZoraTimedSaleStrategy} from "../src/interfaces/IZoraTimedSaleStrategy.sol";
import {ZoraTimedSaleStrategy} from "../src/minter/ZoraTimedSaleStrategy.sol";
import {ZoraTimedSaleStrategyImpl} from "../src/minter/ZoraTimedSaleStrategyImpl.sol";
import {IReduceSupply} from "@zoralabs/shared-contracts/interfaces/IReduceSupply.sol";

import {ProtocolRewards} from "./mock/ProtocolRewards.sol";
import {ICreatorRoyaltiesControl} from "./mock/ICreatorRoyaltiesControl.sol";
import {Zora1155} from "./mock/Zora1155.sol";
import {Zora1155 as Zora1155NoReduceSupply} from "./mock/Zora1155NoReduceSupply.sol";
import {Royalties} from "../src/royalties/Royalties.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

/** // TODO (later) store uniswap deployments in a config file for multichain forking
 *  Zora Mainnet
 * {
 *   "v3CoreFactoryAddress": "0x7145F8aeef1f6510E92164038E1B6F8cB2c42Cbb",
 *   "swapRouter02": "0x7De04c96BE5159c3b5CeffC82aa176dc81281557",
 *   "multicall2Address": "0xA51c76bEE6746cB487a7e9312E43e2b8f4A37C15",
 *   "proxyAdminAddress": "0xd4109824FC80dD41ca6ee8D304ec74B8bEdEd03b",
 *   "tickLensAddress": "0x209AAda09D74Ad3B8D0E92910Eaf85D2357e3044",
 *   "nftDescriptorLibraryAddressV1_3_0": "0xffF2BffC03474F361B7f92cCfF2fD01CFBBDCdd1",
 *   "nonfungibleTokenPositionDescriptorAddressV1_3_0": "0xf15D9e794d39A3b4Ea9EfC2376b2Cd9562996422",
 *   "descriptorProxyAddress": "0x843b0b03c3B3B0434B9cb00AD9cD1D9218E7741b", //
 *   "nonfungibleTokenPositionManagerAddress": "0xbC91e8DfA3fF18De43853372A3d7dfe585137D78",
 *   "v3MigratorAddress": "0x048352d8dCF13686982C799da63fA6426a9D0b60",
 *   "v3StakerAddress": "0x5eF5A6923d2f566F65f363b78EF7A88ab1E4206f",
 *   "quoterV2Address": "0x11867e1b3348F3ce4FcC170BC5af3d23E07E64Df",
 * }
 */
contract BaseTest is Test {
    address internal constant DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address internal constant WETH_ADDRESS = 0x4200000000000000000000000000000000000006;
    address internal constant PROTOCOL_REWARDS = 0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B;
    address internal constant ZORA_1155_FACTORY = 0x777777C338d93e2C7adf08D102d45CA7CC4Ed021;

    uint256 internal constant mintFee = 0.000111 ether;
    uint256 internal constant royaltyFeeBps = 2500;
    uint256 constant ONE_ERC20 = 1e18;

    uint64 internal constant DEFAULT_MARKET_COUNTDOWN = 3 hours;
    uint256 internal constant DEFAULT_MINIMUM_MARKET_ETH = 0.0111 ether;
    uint256 internal constant DEFAULT_MINIMUM_MINTS = 1000;

    struct Users {
        address owner;
        address zoraRewardRecipient;
        address creator;
        address collector;
        address mintReferral;
        address createReferral;
        address payable royaltyFeeRecipient;
    }

    Users internal users;
    IWETH internal weth;
    INonfungiblePositionManager internal nonfungiblePositionManager;
    ISwapRouter internal swapRouter;
    ProtocolRewards internal protocolRewards;
    ERC20Z internal erc20zImpl;
    ZoraTimedSaleStrategyImpl internal saleStrategyImpl;
    ZoraTimedSaleStrategyImpl internal saleStrategy;
    Zora1155 internal collection;
    Royalties internal royalties;
    uint256 internal tokenId;
    uint256 internal forkId;

    function setUp() public virtual {
        // TODO (later) support multichain forking, which will require a different address for the nonfungiblePositionManager
        forkId = vm.createSelectFork("zora", 17657267);
        nonfungiblePositionManager = INonfungiblePositionManager(0xbC91e8DfA3fF18De43853372A3d7dfe585137D78);
        swapRouter = ISwapRouter(0x7De04c96BE5159c3b5CeffC82aa176dc81281557);
        weth = IWETH(WETH_ADDRESS);

        users.owner = makeAddr("owner");
        users.zoraRewardRecipient = makeAddr("zoraRewardRecipient");
        users.creator = makeAddr("creator");
        users.collector = makeAddr("collector");
        users.mintReferral = makeAddr("mintReferral");
        users.createReferral = makeAddr("createReferral");
        users.royaltyFeeRecipient = payable(makeAddr("royaltyFeeRecipient"));

        protocolRewards = new ProtocolRewards();
        vm.etch(PROTOCOL_REWARDS, address(protocolRewards).code);

        royalties = new Royalties();
        royalties.initialize(weth, nonfungiblePositionManager, users.royaltyFeeRecipient, royaltyFeeBps);
        erc20zImpl = new ERC20Z(royalties);
        saleStrategyImpl = new ZoraTimedSaleStrategyImpl();
        saleStrategy = ZoraTimedSaleStrategyImpl(address(new ZoraTimedSaleStrategy(address(saleStrategyImpl))));
        saleStrategy.initialize(users.owner, users.zoraRewardRecipient, address(erc20zImpl), IProtocolRewards(address(protocolRewards)));

        vm.startPrank(users.creator);

        collection = new Zora1155(users.creator, address(saleStrategy));
        tokenId = collection.setupNewTokenWithCreateReferral("token.uri", type(uint256).max, users.createReferral);
        collection.addPermission(tokenId, address(saleStrategy), collection.PERMISSION_BIT_MINTER());

        vm.stopPrank();

        vm.label(PROTOCOL_REWARDS, "PROTOCOL_REWARDS");
        vm.label(address(nonfungiblePositionManager), "NONFUNGIBLE_POSITION_MANAGER");
        vm.label(address(swapRouter), "SWAP_ROUTER");
        vm.label(address(royalties), "ROYALTIES");
        vm.label(address(saleStrategy), "SALE_STRATEGY");
        vm.label(address(collection), "1155_COLLECTION");
    }

    function setUpERC20z() public returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(collection, tokenId, msg.sender, block.number, block.prevrandao, block.timestamp, tx.gasprice));
        address erc20zAddress = Clones.cloneDeterministic(address(erc20zImpl), salt);
        vm.prank(users.creator);
        IERC20Z(erc20zAddress).initialize(address(collection), tokenId, "TestName", "TestSymbol");
        return erc20zAddress;
    }
}
