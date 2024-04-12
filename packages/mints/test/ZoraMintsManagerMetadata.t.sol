// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {IZoraMints1155, IZoraMints1155Errors} from "../src/interfaces/IZoraMints1155.sol";
import {ZoraMints1155} from "../src/ZoraMints1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ReceiveRejector} from "@zoralabs/shared-contracts/mocks/ReceiveRejector.sol";
import {MockPreminter} from "./mocks/MockPreminter.sol";
import {ZoraMintsFixtures} from "./fixtures/ZoraMintsFixtures.sol";
import {TokenConfig} from "../src/ZoraMintsTypes.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ZoraMintsManagerImpl, TokenConfig} from "../src/ZoraMintsManagerImpl.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ZoraMintsManager} from "../src/ZoraMintsManager.sol";
import {IZoraMintsURIManager} from "../src/interfaces/IZoraMintsURIManager.sol";
import {IZoraCreator1155PremintExecutorV2} from "@zoralabs/shared-contracts/interfaces/IZoraCreator1155PremintExecutorV2.sol";

contract ZoraMintsManagerMetadataTest is Test {
    event URIsUpdated(string contractURI, string baseURI);
    event ContractURIUpdated();
    event URI(string value, uint256 indexed id);

    address defaultOwner = address(0x13);
    ZoraMintsManagerImpl zoraMintsManager;
    IZoraMints1155 mints;

    uint256[] tokenIds;

    function setUp() public {
        bytes memory mintsCreationCode = abi.encodePacked(type(ZoraMints1155).creationCode);
        ZoraMintsManagerImpl managerImpl = new ZoraMintsManagerImpl(IZoraCreator1155PremintExecutorV2(address(0x123)));
        ZoraMintsManager managerProxy = new ZoraMintsManager(address(managerImpl));
        zoraMintsManager = ZoraMintsManagerImpl(address(managerProxy));
        mints = zoraMintsManager.initialize({
            defaultOwner: defaultOwner,
            zoraMintsSalt: bytes32("0xabcdef"),
            zoraMintsCreationCode: mintsCreationCode,
            initialEthTokenId: 1,
            initialEthTokenPrice: 0.001 ether,
            newBaseURI: "",
            newContractURI: ""
        });

        tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 5;
    }

    function testMetadataDeploysCorrectly() public {
        assertEq(zoraMintsManager.uri(1), "1");
        assertEq(zoraMintsManager.contractURI(), "");
        vm.expectEmit(true, true, true, true);
        emit URIsUpdated({contractURI: "https://zora.co/mints/metadata/contract.json", baseURI: "https://zora.co/mints/metadata/"});
        vm.prank(defaultOwner);
        zoraMintsManager.setMetadataURIs("https://zora.co/mints/metadata/contract.json", "https://zora.co/mints/metadata/", tokenIds);
        assertEq(zoraMintsManager.uri(1), "https://zora.co/mints/metadata/1");
        assertEq(zoraMintsManager.contractURI(), "https://zora.co/mints/metadata/contract.json");
    }

    function testManagerContractMetadata() public {
        assertEq(zoraMintsManager.contractName(), "Zora Mints Manager");
    }

    function testMetadataCannotBeUpdatedNonOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", address(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496)));
        zoraMintsManager.setMetadataURIs("https://zora.co/mints/metadata/contract.json", "https://zora.co/mints/metadata/", tokenIds);
    }

    function testZoraNFTEmitsContractURI() public {
        vm.expectEmit(true, true, true, true);
        emit ContractURIUpdated();
        vm.prank(defaultOwner);
        zoraMintsManager.setMetadataURIs("https://zora.co/mints/metadata/contract.json", "https://zora.co/mints/metadata/", tokenIds);
    }

    function testZoraNFTNotifiesNewTokenURI() public {
        vm.prank(defaultOwner);
        vm.expectEmit(true, true, true, true);
        emit URI("2", 2);
        zoraMintsManager.createToken(2, TokenConfig({price: 0.01 ether, tokenAddress: address(0), redeemHandler: address(0)}), false);
    }

    function testMintsMetadataUpdate_zora() public {
        string memory newContractURI = "https://zora.co/assets/mints/metadata";
        string memory newBaseURI = "https://zora.co/assets/mints/metadata/";

        tokenIds = new uint256[](1);

        tokenIds[0] = 1;

        bytes memory setNewUrlsCall = abi.encodeWithSelector(ZoraMintsManagerImpl.setMetadataURIs.selector, newContractURI, newBaseURI, tokenIds);

        vm.startPrank(zoraMintsManager.owner());

        (bool success, ) = address(zoraMintsManager).call(setNewUrlsCall);

        assertTrue(success);
        assertEq(ZoraMints1155(address(zoraMintsManager.zoraMints1155())).contractURI(), newContractURI);
        assertEq(ZoraMints1155(address(zoraMintsManager.zoraMints1155())).uri(1), "https://zora.co/assets/mints/metadata/1");

        console2.log("update urls call:");
        console2.log(vm.toString(setNewUrlsCall));
    }
}
