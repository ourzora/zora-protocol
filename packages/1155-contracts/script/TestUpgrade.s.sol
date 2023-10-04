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
import {ZoraCreatorRedeemMinterFactory} from "../src/minters/redeem/ZoraCreatorRedeemMinterFactory.sol";
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
        ZoraCreator1155FactoryImpl factory = ZoraCreator1155FactoryImpl(payable(configFile.readAddress(".FACTORY_PROXY")));
        vm.prank(factory.owner());
        factory.upgradeTo(address(0xfca4587FAf3a32eBE2F05c9D044aEF072031A796));
        vm.expectRevert();
        factory.upgradeTo(address(0xfca4587FAf3a32eBE2F05c9D044aEF072031A796));
        vm.prank(factory.owner());
        factory.upgradeTo(address(0xfca4587FAf3a32eBE2F05c9D044aEF072031A796));
        console2.log(factory.owner());
    }
}
