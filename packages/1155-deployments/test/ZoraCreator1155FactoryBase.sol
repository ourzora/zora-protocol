// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {IZoraCreator1155Factory} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreator1155FactoryImpl} from "@zoralabs/zora-1155-contracts/src/factory/ZoraCreator1155FactoryImpl.sol";
import {IZoraCreator1155Errors} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155Errors.sol";
import {IZoraCreator1155} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155.sol";
import {ZoraCreator1155Impl} from "@zoralabs/zora-1155-contracts/src/nft/ZoraCreator1155Impl.sol";
import {IMinter1155} from "@zoralabs/zora-1155-contracts/src/interfaces/IMinter1155.sol";
import {IOwnable} from "@zoralabs/zora-1155-contracts/src/interfaces/IOwnable.sol";
import {ICreatorRoyaltiesControl} from "@zoralabs/zora-1155-contracts/src/interfaces/ICreatorRoyaltiesControl.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "@zoralabs/zora-1155-contracts/src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {ForkDeploymentConfig, Deployment} from "../src/DeploymentConfig.sol";

contract ZoraCreator1155FactoryBase is ForkDeploymentConfig, Test {
    uint256 constant quantityToMint = 3;
    uint256 constant tokenMaxSupply = 100;
    uint32 constant royaltyMintSchedule = 10;
    uint32 constant royaltyBPS = 100;
    uint256 constant mintFee = 0.000777 ether;

    address collector;
    address creator;

    uint256 public constant PERMISSION_BIT_MINTER = 2 ** 2;

    function setUp() external {
        creator = vm.addr(1);
        collector = vm.addr(2);
    }

    function _setupToken(IZoraCreator1155 target, IMinter1155 fixedPrice, uint96 tokenPrice) private returns (uint256 tokenId) {
        string memory tokenURI = "ipfs://token";

        tokenId = target.setupNewToken(tokenURI, tokenMaxSupply);

        target.addPermission(tokenId, address(fixedPrice), PERMISSION_BIT_MINTER);

        target.callSale(
            tokenId,
            fixedPrice,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                tokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: tokenPrice,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );
    }

    function _createErc1155Contract(IZoraCreator1155Factory factory) private returns (IZoraCreator1155 target) {
        // create the contract, with no toekns
        bytes[] memory initSetup = new bytes[](0);

        address admin = creator;
        string memory contractURI = "ipfs://asdfasdf";
        string memory name = "Test";
        address royaltyRecipient = creator;

        address deployedAddress = factory.createContract(
            contractURI,
            name,
            ICreatorRoyaltiesControl.RoyaltyConfiguration({
                royaltyBPS: royaltyBPS,
                royaltyRecipient: royaltyRecipient,
                royaltyMintSchedule: royaltyMintSchedule
            }),
            payable(admin),
            initSetup
        );

        target = IZoraCreator1155(deployedAddress);

        // ** 2. Setup a new token with the fixed price sales strategy **
    }

    function mintTokenAtFork(IZoraCreator1155Factory factory) internal {
        uint96 tokenPrice = 1 ether;
        IMinter1155 fixedPrice = factory.defaultMinters()[0];
        // now create a contract with the factory
        vm.startPrank(creator);

        // ** 1. Create the erc1155 contract **
        IZoraCreator1155 target = _createErc1155Contract(factory);

        // ** 2. Setup a new token with the fixed price sales strategy and the token price **
        uint256 tokenId = _setupToken(target, fixedPrice, tokenPrice);

        // ** 3. Mint on that contract **

        // mint 3 tokens
        uint256 valueToSend = quantityToMint * (tokenPrice + mintFee);

        // mint the token
        vm.deal(collector, valueToSend);
        vm.startPrank(collector);
        ZoraCreator1155Impl(payable(address(target))).mintWithRewards{value: valueToSend}(
            fixedPrice,
            tokenId,
            quantityToMint,
            abi.encode(collector),
            address(0)
        );

        uint256 balance = ZoraCreator1155Impl(payable(address(target))).balanceOf(collector, tokenId);

        assertEq(balance, quantityToMint, "balance mismatch");
    }

    function canCreateContractAndMint() internal {
        Deployment memory deployment = getDeployment();

        address factoryAddress = deployment.factoryProxy;
        ZoraCreator1155FactoryImpl factory = ZoraCreator1155FactoryImpl(factoryAddress);

        assertEq(getChainConfig().factoryOwner, IOwnable(factoryAddress).owner(), "incorrect owner");

        // make sure that the address from the factory matches the stored fixed price address
        // sanity check - check minters match config
        assertEq(address(factory.merkleMinter()), deployment.merkleMintSaleStrategy, "merkle minter incorrect");
        assertEq(address(factory.fixedPriceMinter()), deployment.fixedPriceSaleStrategy, "fixed priced minter incorrect");
        assertEq(address(factory.redeemMinterFactory()), deployment.redeemMinterFactory, "redeem minter not correct");
    }
}
