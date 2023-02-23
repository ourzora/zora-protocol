// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ZoraCreator1155Impl} from "../../../src/nft/ZoraCreator1155Impl.sol";
import {ZoraCreator1155Proxy} from "../../../src/proxies/ZoraCreator1155Proxy.sol";
import {IZoraCreator1155} from "../../../src/interfaces/IZoraCreator1155.sol";
import {IRenderer1155} from "../../../src/interfaces/IRenderer1155.sol";
import {ICreatorRoyaltiesControl} from "../../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../../../src/interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreatorMerkleMinterStrategy} from "../../../src/minters/merkle/ZoraCreatorMerkleMinterStrategy.sol";

contract ZoraCreatorMerkleMinterStrategyTest is Test {
    ZoraCreator1155Impl internal target;
    ZoraCreatorMerkleMinterStrategy internal merkleMinter;
    address internal admin = address(0x999);

    function setUp() external {
        bytes[] memory emptyData = new bytes[](0);
        ZoraCreator1155Impl targetImpl = new ZoraCreator1155Impl(0, address(0));
        ZoraCreator1155Proxy proxy = new ZoraCreator1155Proxy(address(targetImpl));
        target = ZoraCreator1155Impl(address(proxy));
        target.initialize("test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, address(0)), admin, emptyData);
        merkleMinter = new ZoraCreatorMerkleMinterStrategy();
    }
}
