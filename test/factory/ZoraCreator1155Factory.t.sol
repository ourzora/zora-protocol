// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ZoraCreator1155FactoryImpl, InvalidDelegateSignature, InvalidNonce} from "../../src/factory/ZoraCreator1155FactoryImpl.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155Factory} from "../../src/proxies/Zora1155Factory.sol";
import {IZoraCreator1155Factory} from "../../src/interfaces/IZoraCreator1155Factory.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {MockContractMetadata} from "../mock/MockContractMetadata.sol";

import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import {Create2Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/Create2Upgradeable.sol";

contract ZoraCreator1155FactoryTest is Test {
    ZoraCreator1155FactoryImpl internal factory;

    function setUp() external {
        ZoraCreator1155Impl zoraCreator1155Impl = new ZoraCreator1155Impl(0, address(0), address(0));
        factory = new ZoraCreator1155FactoryImpl(zoraCreator1155Impl, IMinter1155(address(1)), IMinter1155(address(2)), IMinter1155(address(3)));
    }

    function test_contractVersion() external {
        assertEq(factory.contractVersion(), "1.3.0");
    }

    function test_contractName() external {
        assertEq(factory.contractName(), "ZORA 1155 Contract Factory");
    }

    function test_contractURI() external {
        assertEq(factory.contractURI(), "https://github.com/ourzora/zora-1155-contracts/");
    }

    function test_initialize(address initialOwner) external {
        vm.assume(initialOwner != address(0));
        address payable proxyAddress = payable(
            address(new Zora1155Factory(address(factory), abi.encodeWithSelector(ZoraCreator1155FactoryImpl.initialize.selector, initialOwner)))
        );
        ZoraCreator1155FactoryImpl proxy = ZoraCreator1155FactoryImpl(proxyAddress);
        assertEq(proxy.owner(), initialOwner);
    }

    function test_defaultMinters() external {
        IMinter1155[] memory minters = factory.defaultMinters();
        assertEq(minters.length, 3);
        assertEq(address(minters[0]), address(2));
        assertEq(address(minters[1]), address(1));
        assertEq(address(minters[2]), address(3));
    }

    function test_createContract(
        string memory contractURI,
        string memory name,
        uint32 royaltyBPS,
        uint32 royaltyMintSchedule,
        address royaltyRecipient,
        address payable admin
    ) external {
        // If the factory is the admin, the admin flag is cleared
        // during multicall breaking a further test assumption.
        // Additionally, this case makes no sense from a user perspective.
        vm.assume(admin != payable(address(factory)));
        vm.assume(royaltyMintSchedule != 1);
        // Assume royalty recipient is not 0
        vm.assume(royaltyRecipient != payable(address(0)));
        bytes[] memory initSetup = new bytes[](1);
        initSetup[0] = abi.encodeWithSelector(IZoraCreator1155.setupNewToken.selector, "ipfs://asdfadsf", 100);
        address deployedAddress = factory.createContract(
            contractURI,
            name,
            ICreatorRoyaltiesControl.RoyaltyConfiguration({
                royaltyBPS: royaltyBPS,
                royaltyRecipient: royaltyRecipient,
                royaltyMintSchedule: royaltyMintSchedule
            }),
            admin,
            initSetup
        );
        ZoraCreator1155Impl target = ZoraCreator1155Impl(deployedAddress);

        ICreatorRoyaltiesControl.RoyaltyConfiguration memory config = target.getRoyalties(0);
        assertEq(config.royaltyMintSchedule, royaltyMintSchedule);
        assertEq(config.royaltyBPS, royaltyBPS);
        assertEq(config.royaltyRecipient, royaltyRecipient);
        assertEq(target.getPermissions(0, admin), target.PERMISSION_BIT_ADMIN());
        assertEq(target.uri(1), "ipfs://asdfadsf");
    }

    function test_upgrade(address initialOwner) external {
        vm.assume(initialOwner != address(0));

        IZoraCreator1155 mockNewContract = IZoraCreator1155(address(0x999));

        ZoraCreator1155FactoryImpl newFactoryImpl = new ZoraCreator1155FactoryImpl(
            mockNewContract,
            IMinter1155(address(0)),
            IMinter1155(address(0)),
            IMinter1155(address(0))
        );

        address payable proxyAddress = payable(
            address(new Zora1155Factory(address(factory), abi.encodeWithSelector(ZoraCreator1155FactoryImpl.initialize.selector, initialOwner)))
        );
        ZoraCreator1155FactoryImpl proxy = ZoraCreator1155FactoryImpl(proxyAddress);
        vm.prank(initialOwner);
        proxy.upgradeTo(address(newFactoryImpl));
        assertEq(address(proxy.implementation()), address(mockNewContract));
    }

    function test_upgradeFailsWithDifferentContractName(address initialOwner) external {
        vm.assume(initialOwner != address(0));

        MockContractMetadata mockContractMetadata = new MockContractMetadata("ipfs://asdfadsf", "name");

        address payable proxyAddress = payable(
            address(new Zora1155Factory(address(factory), abi.encodeWithSelector(ZoraCreator1155FactoryImpl.initialize.selector, initialOwner)))
        );
        ZoraCreator1155FactoryImpl proxy = ZoraCreator1155FactoryImpl(proxyAddress);
        vm.prank(initialOwner);
        vm.expectRevert(abi.encodeWithSignature("UpgradeToMismatchedContractName(string,string)", "ZORA 1155 Contract Factory", "name"));
        proxy.upgradeTo(address(mockContractMetadata));
    }

    // we dont need a nonce - we can deterministically determine the created contract address - and ensure its not created twice
    // we can recover the address of the creator using ec recover
    // can we use create2? - since we are using an upgradeable contract, the new contract is created
    // with just the implementation as an argument. We can't use create2 to deterministically create the contract
    // what about an end date?

    function test_delegateCreateContract_succeedsWithValidSignature() external {
        // generate a signature for desired contract

        string memory contractUri = "ipfs://asdfadsf";
        string memory name = "asdfasdf";
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory royaltyConfig = _createExampleRoyaltyConfig();

        bytes[] memory initSetup = _createExampleInitSetup();

        uint256 creatorPrivateKey = 0xA11CE;

        address payable creator = payable(vm.addr(creatorPrivateKey));

        // generate hash of arguments for contract creation
        bytes32 digest = factory.delegateCreateContractHashTypeData(creator, contractUri, name, royaltyConfig, initSetup);

        // generate signature for hash using creators private key
        bytes memory signature = _sign(creatorPrivateKey, digest);

        address executor = vm.addr(100);
        vm.prank(executor);

        // someone else creates the contract - the signature must have been generated using these same arguments
        address createdContract = factory.delegateCreateContract(creator, contractUri, name, royaltyConfig, initSetup, signature);

        ZoraCreator1155Impl target = ZoraCreator1155Impl(createdContract);

        // validate that the owner/admin of the created contract is the original signer.
        assertEq(target.owner(), creator);
    }

    function test_delegateCreateContract_failsWithBadArguments(
        bool badCreator,
        bool badContractUri,
        bool badName,
        bool badRoyaltyConfig,
        bool badInitSetup,
        bool badSignature
    ) external {
        string memory contractUri = "ipfs://asdfadsf";
        string memory name = "asdfasdf";
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory royaltyConfig = _createExampleRoyaltyConfig();

        bytes[] memory initSetup = _createExampleInitSetup();

        uint256 creatorPrivateKey = 0xA11CE;

        address payable creator = payable(vm.addr(creatorPrivateKey));

        bytes32 digest = factory.delegateCreateContractHashTypeData(creator, contractUri, name, royaltyConfig, initSetup);

        bytes memory signature = _sign(creatorPrivateKey, digest);

        if (badSignature) {
            // change the signature to be invalid
            signature[0] = 0x00;
        }

        // if any of the fuzzy parameters indicate a bad arg, then we change the arg to be a mismatch from the sign, and we should
        // get an error on the creation of the contract
        address newCreator = badCreator ? vm.addr(1000) : creator;
        string memory newContractUriString = badContractUri ? "asdfasdf" : contractUri;
        string memory newNameString = badName ? "adf" : name;
        if (badRoyaltyConfig) {
            royaltyConfig.royaltyBPS = 10;
        }

        if (badInitSetup) {
            initSetup[0] = abi.encodeWithSelector(IZoraCreator1155.setupNewToken.selector, "ipfs://", 1);
        }

        // if any are bad, then expect revert
        if (badSignature) {
            // todo: figure out specific errors for bad signature
            vm.expectRevert();
        } else if (badCreator || badContractUri || badName || badRoyaltyConfig || badInitSetup) {
            vm.expectRevert(InvalidDelegateSignature.selector);
        }

        // call delegate create with new args
        factory.delegateCreateContract(payable(newCreator), newContractUriString, newNameString, royaltyConfig, initSetup, signature);
    }

    function test_delegateCreateContract_signatureCannotBeExecutedTwice() external {
        string memory contractUri = "ipfs://asdfadsf";
        string memory name = "asdfasdf";
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory royaltyConfig = _createExampleRoyaltyConfig();

        bytes[] memory initSetup = _createExampleInitSetup();

        uint256 creatorPrivateKey = 0xA11CE;

        address payable creator = payable(vm.addr(creatorPrivateKey));

        bytes32 digest = factory.delegateCreateContractHashTypeData(creator, contractUri, name, royaltyConfig, initSetup);

        bytes memory signature = _sign(creatorPrivateKey, digest);

        factory.delegateCreateContract(creator, contractUri, name, royaltyConfig, initSetup, signature);

        vm.expectRevert();

        factory.delegateCreateContract(creator, contractUri, name, royaltyConfig, initSetup, signature);
    }

    function test_canDetermineContractAddress() external {
        string memory contractUri = "ipfs://asdfadsf";
        string memory name = "asdfasdf";
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory royaltyConfig = _createExampleRoyaltyConfig();

        bytes[] memory initSetup = _createExampleInitSetup();

        uint256 creatorPrivateKey = 0xA11CE;

        address payable creator = payable(vm.addr(creatorPrivateKey));

        bytes32 digest = factory.delegateCreateContractHashTypeData(creator, contractUri, name, royaltyConfig, initSetup);

        bytes memory signature = _sign(creatorPrivateKey, digest);

        address createdAddress = factory.delegateCreateContract(creator, contractUri, name, royaltyConfig, initSetup, signature);

        address expectedAddress = factory.computeDelegateCreatedContractAddress(digest);

        console.log(expectedAddress);

        assertEq(createdAddress, expectedAddress);
    }

    function _sign(uint256 privateKey, bytes32 digest) private pure returns (bytes memory) {
        // sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // combine into a single bytes array
        return abi.encodePacked(r, s, v);
    }

    function _createExampleRoyaltyConfig() private pure returns (ICreatorRoyaltiesControl.RoyaltyConfiguration memory) {
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory royaltyConfig = ICreatorRoyaltiesControl.RoyaltyConfiguration({
            royaltyBPS: 100,
            royaltyRecipient: address(0x123),
            royaltyMintSchedule: 0
        });

        return royaltyConfig;
    }

    function _createExampleInitSetup() private pure returns (bytes[] memory) {
        bytes[] memory initSetup = new bytes[](1);
        initSetup[0] = abi.encodeWithSelector(IZoraCreator1155.setupNewToken.selector, "ipfs://asdfadsf", 100);

        return initSetup;
    }
}
