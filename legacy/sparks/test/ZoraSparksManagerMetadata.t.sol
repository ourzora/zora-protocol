// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {IZoraSparks1155, IZoraSparks1155Errors} from "../src/interfaces/IZoraSparks1155.sol";
import {ZoraSparks1155} from "../src/ZoraSparks1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ReceiveRejector} from "@zoralabs/shared-contracts/mocks/ReceiveRejector.sol";
import {ZoraSparksFixtures} from "./fixtures/ZoraSparksFixtures.sol";
import {TokenConfig} from "../src/ZoraSparksTypes.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ZoraSparksManagerImpl, TokenConfig} from "../src/ZoraSparksManagerImpl.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ZoraSparksManager} from "../src/ZoraSparksManager.sol";
import {IZoraSparksURIManager} from "../src/interfaces/IZoraSparksURIManager.sol";

contract ZoraSparksManagerMetadataTest is Test {
    event URIsUpdated(string contractURI, string baseURI);
    event ContractURIUpdated();
    event URI(string value, uint256 indexed id);

    address defaultOwner = address(0x13);
    ZoraSparksManagerImpl zoraSparksManager;
    IZoraSparks1155 sparks;

    uint256[] tokenIds;

    function setUp() public {
        bytes memory sparksCreationCode = abi.encodePacked(type(ZoraSparks1155).creationCode);
        ZoraSparksManagerImpl managerImpl = new ZoraSparksManagerImpl();
        ZoraSparksManager managerProxy = new ZoraSparksManager(address(managerImpl));
        zoraSparksManager = ZoraSparksManagerImpl(address(managerProxy));
        sparks = zoraSparksManager.initialize({
            defaultOwner: defaultOwner,
            zoraSparksSalt: bytes32("0xabcdef"),
            zoraSparksCreationCode: sparksCreationCode,
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
        assertEq(zoraSparksManager.uri(1), "1");
        assertEq(zoraSparksManager.contractURI(), "");
        vm.expectEmit(true, true, true, true);
        emit URIsUpdated({contractURI: "https://zora.co/sparks/metadata/contract.json", baseURI: "https://zora.co/sparks/metadata/"});
        vm.prank(defaultOwner);
        zoraSparksManager.setMetadataURIs("https://zora.co/sparks/metadata/contract.json", "https://zora.co/sparks/metadata/", tokenIds);
        assertEq(zoraSparksManager.uri(1), "https://zora.co/sparks/metadata/1");
        assertEq(zoraSparksManager.contractURI(), "https://zora.co/sparks/metadata/contract.json");
    }

    function testManagerContractMetadata() public {
        assertEq(zoraSparksManager.contractName(), "Zora Sparks Manager");
    }

    function testMetadataCannotBeUpdatedNonOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", address(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496)));
        zoraSparksManager.setMetadataURIs("https://zora.co/sparks/metadata/contract.json", "https://zora.co/sparks/metadata/", tokenIds);
    }

    function testZoraNFTEmitsContractURI() public {
        vm.expectEmit(true, true, true, true);
        emit ContractURIUpdated();
        vm.prank(defaultOwner);
        zoraSparksManager.setMetadataURIs("https://zora.co/sparks/metadata/contract.json", "https://zora.co/sparks/metadata/", tokenIds);
    }

    function testZoraNFTNotifiesNewTokenURI() public {
        vm.prank(defaultOwner);
        vm.expectEmit(true, true, true, true);
        emit URI("2", 2);
        zoraSparksManager.createToken(2, TokenConfig({price: 0.01 ether, tokenAddress: address(0), redeemHandler: address(0)}));
    }

    function testSparksMetadataUpdate_zora() public {
        string memory newContractURI = "https://zora.co/assets/sparks/metadata";
        string memory newBaseURI = "https://zora.co/assets/sparks/metadata/";

        tokenIds = new uint256[](1);

        tokenIds[0] = 1;

        bytes memory setNewUrlsCall = abi.encodeWithSelector(ZoraSparksManagerImpl.setMetadataURIs.selector, newContractURI, newBaseURI, tokenIds);

        vm.startPrank(zoraSparksManager.owner());

        (bool success, ) = address(zoraSparksManager).call(setNewUrlsCall);

        assertTrue(success);
        assertEq(ZoraSparks1155(address(zoraSparksManager.zoraSparks1155())).contractURI(), newContractURI);
        assertEq(ZoraSparks1155(address(zoraSparksManager.zoraSparks1155())).uri(1), "https://zora.co/assets/sparks/metadata/1");

        console2.log("update urls call:");
        console2.log(vm.toString(setNewUrlsCall));
    }
}
