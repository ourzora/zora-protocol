// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraCreator1155FactoryImpl} from "../src/factory/ZoraCreator1155FactoryImpl.sol";
import {Zora1155Factory} from "../src/proxies/Zora1155Factory.sol";
import {ZoraCreator1155Impl} from "../src/nft/ZoraCreator1155Impl.sol";
import {ICreatorRoyaltiesControl} from "../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../src/interfaces/IZoraCreator1155Factory.sol";
import {IMinter1155} from "../src/interfaces/IMinter1155.sol";
import {IZoraCreator1155} from "../src/interfaces/IZoraCreator1155.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {ProxyShim} from "../src/utils/ProxyShim.sol";
import {ZoraCreatorMerkleMinterStrategy} from "../src/minters/merkle/ZoraCreatorMerkleMinterStrategy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract TestUpgrade is Script {
    using stdJson for string;

    string configFile;

    function setUp() public {
        uint256 chainID = 1;
        configFile = vm.readFile(string.concat("./addresses/", Strings.toString(chainID), ".json"));
    }

    function run() public {
        ZoraCreator1155FactoryImpl factory = ZoraCreator1155FactoryImpl(configFile.readAddress(".FACTORY_PROXY"));

        address newImpl = vm.envAddress("NEW_FACTORY_IMPL");

        console2.log("Old 1155 impl", address(factory.implementation()));
        vm.prank(factory.owner());
        factory.upgradeTo(address(newImpl));
        console2.log("New 1155 impl", address(factory.implementation()));
        console2.log("Factory Proxy Address", address(factory));

        address admin = address(0x131);

        bytes[] memory setupActions = new bytes[](0);

        vm.startPrank(admin);

        address newContract = factory.createContract("", "", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), payable(admin), setupActions);

        ZoraCreator1155Impl creator = ZoraCreator1155Impl(newContract);
        creator.setupNewToken("", 100);
        creator.adminMint(address(0x132), 1, 1, "");
        assert(creator.balanceOf(address(0x132), 1) == 1);
    }
}
