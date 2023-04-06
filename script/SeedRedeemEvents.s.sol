// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import {Test} from "forge-std/Test.sol";

import "forge-std/Script.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {ERC721PresetMinterPauserAutoId} from "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";
import {ERC1155PresetMinterPauser} from "@openzeppelin/contracts/token/ERC1155/presets/ERC1155PresetMinterPauser.sol";

import {ZoraCreator1155FactoryImpl} from "../src/factory/ZoraCreator1155FactoryImpl.sol";
import {Zora1155} from "../src/proxies/Zora1155.sol";
import {ProxyShim} from "../src/utils/ProxyShim.sol";
import {Zora1155Factory} from "../src/proxies/Zora1155Factory.sol";
import {ZoraCreator1155Impl} from "../src/nft/ZoraCreator1155Impl.sol";
import {ICreatorRoyaltiesControl} from "../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../src/interfaces/IZoraCreator1155Factory.sol";
import {IMinter1155} from "../src/interfaces/IMinter1155.sol";
import {IZoraCreator1155} from "../src/interfaces/IZoraCreator1155.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {ZoraCreatorMerkleMinterStrategy} from "../src/minters/merkle/ZoraCreatorMerkleMinterStrategy.sol";
import {ZoraCreatorRedeemMinterFactory} from "../src/minters/redeem/ZoraCreatorRedeemMinterFactory.sol";
import {ZoraCreatorRedeemMinterStrategy} from "../src/minters/redeem/ZoraCreatorRedeemMinterStrategy.sol";

contract SeedRedeemEvents is Script, Test {
    function run() public {
        address payable deployer = payable(vm.envAddress("DEPLOYER_ADDRESS"));
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        ZoraCreatorFixedPriceSaleStrategy fixedPricedMinter = new ZoraCreatorFixedPriceSaleStrategy();
        ZoraCreatorMerkleMinterStrategy merkleMinter = new ZoraCreatorMerkleMinterStrategy();
        ZoraCreatorRedeemMinterFactory redeemMinterFactory = new ZoraCreatorRedeemMinterFactory();

        address factoryShimAddress = address(new ProxyShim(deployer));
        Zora1155Factory factoryProxy = new Zora1155Factory(factoryShimAddress, "");

        ZoraCreator1155Impl creatorImpl = new ZoraCreator1155Impl(0, address(0), address(factoryProxy));

        ZoraCreator1155FactoryImpl factoryImpl = new ZoraCreator1155FactoryImpl({
            _implementation: creatorImpl,
            _merkleMinter: merkleMinter,
            _redeemMinterFactory: redeemMinterFactory,
            _fixedPriceMinter: fixedPricedMinter
        });

        ZoraCreator1155FactoryImpl zora1155Factory = ZoraCreator1155FactoryImpl(address(factoryProxy));

        // Upgrade to "real" factory address
        ZoraCreator1155FactoryImpl(address(factoryProxy)).upgradeTo(address(factoryImpl));
        ZoraCreator1155FactoryImpl(address(factoryProxy)).initialize(deployer);

        // existing goerli factories
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory defaultRoyalties;
        // ZoraCreatorRedeemMinterFactory redeemMinterFactory = ZoraCreatorRedeemMinterFactory(0xE29a6D771df7d614ECBe5EBaE4107cf2440AeA9c);

        // test redeem tokens
        // ERC20PresetMinterPauser burnTokenERC20 = ERC20PresetMinterPauser(0xF9E8FF5535AC2296B2155844AdfB8d4Cf5306A73);
        // ERC20PresetMinterPauser burnTokenERC20 = new ERC20PresetMinterPauser("Random Token", "RAND");
        // burnTokenERC20.mint(address(deployer), 1000);
        // ERC1155PresetMinterPauser burnTokenERC1155 = ERC1155PresetMinterPauser(0x7820Accd4a7B9e98a1DC7d8a9965ED0B2C4B39C4);
        ERC1155PresetMinterPauser burnTokenERC1155 = new ERC1155PresetMinterPauser("https://zora.co/testing/token.json");
        burnTokenERC1155.mint(address(deployer), 1, 1000, "");
        // ERC721PresetMinterPauserAutoId burnTokenERC721 = ERC721PresetMinterPauserAutoId(0x5D3d4593a3b80d737e8782100E1f927fAB414DC2);
        // ERC721PresetMinterPauserAutoId burnTokenERC721 = new ERC721PresetMinterPauserAutoId("Test token", "TEST", "https://zora.co/testing/token.json");
        // burnTokenERC721.mint(address(deployer));
        // burnTokenERC721.mint(address(deployer));

        // new 1155
        bytes[] memory emptyBytes;
        // ZoraCreator1155Impl test1155 = ZoraCreator1155Impl(0x14dd495172Ec8F5AB4Cc38d4Ff0a10905f0B3F74);
        ZoraCreator1155Impl test1155 = ZoraCreator1155Impl(zora1155Factory.createContract("https://test.com", "test", defaultRoyalties, deployer, emptyBytes));
        // uint256 newTokenId = 1;
        uint256 newTokenId = test1155.setupNewToken("https://zora.co/testing/token.json", 10);
        test1155.addPermission(0, address(redeemMinterFactory), test1155.PERMISSION_BIT_MINTER());

        // new redeem minter
        address redeemMinterAddress = redeemMinterFactory.predictMinterAddress(address(test1155));
        test1155.callSale(0, redeemMinterFactory, abi.encodeWithSelector(ZoraCreatorRedeemMinterFactory.createMinterIfNoneExists.selector));
        test1155.addPermission(0, redeemMinterAddress, test1155.PERMISSION_BIT_MINTER());
        test1155.addPermission(1, redeemMinterAddress, test1155.PERMISSION_BIT_MINTER());
        ZoraCreatorRedeemMinterStrategy redeemMinter = ZoraCreatorRedeemMinterStrategy(redeemMinterAddress);
        // burnTokenERC20.approve(address(redeemMinter), 500);
        burnTokenERC1155.setApprovalForAll(address(redeemMinter), true);
        // burnTokenERC721.setApprovalForAll(address(redeemMinter), true);
        // create multi-token redeem instructions
        ZoraCreatorRedeemMinterStrategy.MintToken memory mintToken = ZoraCreatorRedeemMinterStrategy.MintToken({
            tokenContract: address(test1155),
            tokenId: newTokenId,
            amount: 1,
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155
        });
        ZoraCreatorRedeemMinterStrategy.RedeemInstruction[] memory instructions = new ZoraCreatorRedeemMinterStrategy.RedeemInstruction[](1);
        // instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
        //     tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC20,
        //     amount: 500,
        //     tokenIdStart: 0,
        //     tokenIdEnd: 0,
        //     tokenContract: address(burnTokenERC20),
        //     transferRecipient: address(0),
        //     burnFunction: bytes4(keccak256(bytes("burnFrom(address,uint256)")))
        // });
        instructions[0] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
            tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC1155,
            amount: 500,
            tokenIdStart: 1,
            tokenIdEnd: 1,
            tokenContract: address(burnTokenERC1155),
            transferRecipient: address(1),
            burnFunction: bytes4(0)
        });
        // instructions[2] = ZoraCreatorRedeemMinterStrategy.RedeemInstruction({
        //     tokenType: ZoraCreatorRedeemMinterStrategy.TokenType.ERC721,
        //     amount: 2,
        //     tokenIdStart: 0,
        //     tokenIdEnd: 1,
        //     tokenContract: address(burnTokenERC721),
        //     transferRecipient: address(0),
        //     burnFunction: bytes4(keccak256(bytes("burn(uint256)")))
        // });
        ZoraCreatorRedeemMinterStrategy.RedeemInstructions memory redeemInstructions = ZoraCreatorRedeemMinterStrategy.RedeemInstructions({
            mintToken: mintToken,
            instructions: instructions,
            saleStart: 0,
            saleEnd: type(uint64).max,
            ethAmount: 0,
            ethRecipient: address(0)
        });

        test1155.callSale(newTokenId, redeemMinter, abi.encodeWithSelector(ZoraCreatorRedeemMinterStrategy.setRedeem.selector, redeemInstructions));

        // purchase via burn to redeem
        uint256[][] memory tokenIds = new uint256[][](1);
        uint256[][] memory amounts = new uint256[][](1);
        // erc20 - 500 amt
        // amounts[0] = new uint256[](1);
        // amounts[0][0] = 500;
        // erc1155 - tokenid 1, 500 amt
        tokenIds[0] = new uint256[](1);
        tokenIds[0][0] = 1;
        amounts[0] = new uint256[](1);
        amounts[0][0] = 500;
        // erc721 - tokenid 0, 1
        // tokenIds[2] = new uint256[](2);
        // tokenIds[2][0] = 0;
        // tokenIds[2][1] = 1;

        test1155.mint(redeemMinter, newTokenId, 1, abi.encode(redeemInstructions, tokenIds, amounts));

        revert("done");
    }
}
