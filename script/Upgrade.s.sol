// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import {ZoraCreator1155FactoryImpl} from "../src/factory/ZoraCreator1155FactoryImpl.sol";
import {Zora1155Factory} from "../src/proxies/Zora1155Factory.sol";
import {ZoraCreator1155Impl} from "../src/nft/ZoraCreator1155Impl.sol";
import {ICreatorRoyaltiesControl} from "../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../src/interfaces/IZoraCreator1155Factory.sol";
import {IMinter1155} from "../src/interfaces/IMinter1155.sol";
import {IZoraCreator1155} from "../src/interfaces/IZoraCreator1155.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {ZoraCreatorMerkleMinterStrategy} from "../src/minters/merkle/ZoraCreatorMerkleMinterStrategy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract UpgradeScript is Script {
    using Strings for uint256;
    using stdJson for string;

    string configFile;

    function setUp() public {
        uint256 chainID = vm.envUint("CHAIN_ID");
        console.log("CHAIN_ID", chainID);

        console2.log("Starting ---");

        configFile = vm.readFile(string.concat("./addresses/", Strings.toString(chainID), ".json"));
    }

    function run() public {
        address payable deployer = payable(vm.envAddress("DEPLOYER"));

        vm.startBroadcast(deployer);

        ZoraCreatorFixedPriceSaleStrategy fixedPriceMinter = ZoraCreatorFixedPriceSaleStrategy(configFile.readAddress(".FIXED_PRICE_SALE_STRATEGY"));
        if (address(fixedPriceMinter) == address(0)) {
            fixedPriceMinter = new ZoraCreatorFixedPriceSaleStrategy();
            console2.log("New FixedPriceMinter", address(fixedPriceMinter));
        } else {
            console2.log("Existing FIXED_PRICE_STRATEGY", address(fixedPriceMinter));
        }
        ZoraCreatorMerkleMinterStrategy merkleMinter = ZoraCreatorMerkleMinterStrategy(configFile.readAddress(".MERKLE_MINT_SALE_STRATEGY"));
        if (address(merkleMinter) == address(0)) {
            merkleMinter = new ZoraCreatorMerkleMinterStrategy();
            console2.log("New MrkleMintStrategy", address(merkleMinter));
        } else {
            console2.log("Existing MERKLE_MINT_STRATEGY", address(merkleMinter));
        }

        address factoryProxy = configFile.readAddress(".FACTORY_PROXY");

        address nftImpl = configFile.readAddress(".1155_IMPL");
        bool isNewNFTImpl = nftImpl == address(0);
        if (isNewNFTImpl) {
            uint256 mintFeeAmount = configFile.readUint(".MINT_FEE_AMOUNT");
            address mintFeeRecipient = configFile.readAddress(".MINT_FEE_RECIPIENT");
            console2.log("mintFeeAmount", mintFeeAmount);
            console2.log("minFeeRecipient", mintFeeRecipient);
            nftImpl = address(new ZoraCreator1155Impl(mintFeeAmount, mintFeeRecipient, factoryProxy));
            console2.log("New NFT_IMPL", nftImpl);
        } else {
            console2.log("Existing NFT_IMPL", nftImpl);
        }

        ZoraCreator1155FactoryImpl factoryImpl = new ZoraCreator1155FactoryImpl({
            _implementation: IZoraCreator1155(nftImpl),
            _merkleMinter: merkleMinter,
            _fixedPriceMinter: fixedPriceMinter
        });

        console2.log("New Factory Impl", address(factoryImpl));
        console2.log("Upgrade to this new factory impl from ", factoryProxy);

        if (isNewNFTImpl) {
            bytes[] memory setup = new bytes[](0);
            address newContract = address(
                IZoraCreator1155Factory(address(factoryProxy)).createContract(
                    "ipfs://bafkreigu544g6wjvqcysurpzy5pcskbt45a5f33m6wgythpgb3rfqi3lzi",
                    "+++",
                    ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyBPS: 0, royaltyRecipient: address(0), royaltyMintSchedule: 0}),
                    deployer,
                    setup
                )
            );
            console2.log("Deploying new contract for verifiation purposes", newContract);
        }
    }
}
