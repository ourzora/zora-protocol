// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {Zora1155FactoryFixtures} from "../fixtures/Zora1155FactoryFixtures.sol";
import {Zora1155PremintFixtures} from "../fixtures/Zora1155PremintFixtures.sol";
import {ZoraCreator1155FactoryImpl} from "../../src/factory/ZoraCreator1155FactoryImpl.sol";
import {Zora1155PremintExecutor} from "../../src/proxies/Zora1155PremintExecutor.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {ZoraCreator1155PremintExecutorImpl} from "../../src/delegation/ZoraCreator1155PremintExecutorImpl.sol";
import {Zora1155Factory} from "../../src/proxies/Zora1155Factory.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {ProxyShim} from "../../src/utils/ProxyShim.sol";
import {ZoraCreator1155Attribution, PremintEncoding, ContractCreationConfig, TokenCreationConfigV2, PremintConfigV2, PremintConfig} from "../../src/delegation/ZoraCreator1155Attribution.sol";
import {IOwnable2StepUpgradeable} from "../../src/utils/ownable/IOwnable2StepUpgradeable.sol";
import {IHasContractName} from "../../src/interfaces/IContractMetadata.sol";
import {ZoraCreator1155PremintExecutorImplLib} from "../../src/delegation/ZoraCreator1155PremintExecutorImplLib.sol";
import {IUpgradeGate} from "../../src/interfaces/IUpgradeGate.sol";
import {IProtocolRewards} from "@zoralabs/shared-contracts/interfaces/IProtocolRewards.sol";
import {IZoraCreator1155PremintExecutor, ILegacyZoraCreator1155PremintExecutor, IRemovedZoraCreator1155PremintExecutorFunctions} from "../../src/interfaces/IZoraCreator1155PremintExecutor.sol";
import {MintArguments} from "@zoralabs/shared-contracts/entities/Premint.sol";

contract Zora1155PremintExecutorProxyTest is Test, IHasContractName {
    address internal owner;
    uint256 internal creatorPrivateKey;
    address internal creator;
    address internal collector;
    address internal zora;
    Zora1155Factory internal factoryProxy;
    ZoraCreator1155FactoryImpl factoryAtProxy;
    ZoraCreator1155PremintExecutorImpl preminterAtProxy;

    MintArguments defaultMintArguments;

    function setUp() external {
        zora = makeAddr("zora");
        owner = makeAddr("owner");
        collector = makeAddr("collector");
        (creator, creatorPrivateKey) = makeAddrAndKey("creator");

        vm.startPrank(zora);
        (, , , factoryProxy, ) = Zora1155FactoryFixtures.setup1155AndFactoryProxy(zora, zora);
        factoryAtProxy = ZoraCreator1155FactoryImpl(address(factoryProxy));
        vm.stopPrank();

        // create preminter implementation
        ZoraCreator1155PremintExecutorImpl preminterImplementation = new ZoraCreator1155PremintExecutorImpl(ZoraCreator1155FactoryImpl(address(factoryProxy)));

        // build the proxy
        Zora1155PremintExecutor proxy = new Zora1155PremintExecutor(address(preminterImplementation), "");

        // access the executor implementation via the proxy, and initialize the admin
        preminterAtProxy = ZoraCreator1155PremintExecutorImpl(address(proxy));
        preminterAtProxy.initialize(owner);

        defaultMintArguments = MintArguments({mintRecipient: collector, mintComment: "blah", mintRewardsRecipients: new address[](0)});
    }

    function test_canInvokeImplementationMethods() external {
        // create premint config
        IMinter1155 fixedPriceMinter = ZoraCreator1155FactoryImpl(address(factoryProxy)).fixedPriceMinter();

        PremintConfigV2 memory premintConfig = PremintConfigV2({
            tokenConfig: Zora1155PremintFixtures.makeDefaultTokenCreationConfigV2(fixedPriceMinter, creator),
            uid: 100,
            version: 0,
            deleted: false
        });

        // now interface with proxy preminter - sign and execute the premint
        ContractCreationConfig memory contractConfig = Zora1155PremintFixtures.makeDefaultContractCreationConfig(creator);
        address deterministicAddress = preminterAtProxy.getContractAddress(contractConfig);

        // sign the premint
        bytes memory signature = _signPremint(ZoraCreator1155Attribution.hashPremint(premintConfig), PremintEncoding.HASHED_VERSION_2, deterministicAddress);

        uint256 quantityToMint = 1;

        uint256 mintFeeAmount = preminterAtProxy.mintFee(deterministicAddress);

        // execute the premint
        vm.deal(collector, mintFeeAmount);
        vm.prank(collector);
        uint256 tokenId = preminterAtProxy
        .premintV2{value: mintFeeAmount}(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments).tokenId;

        assertEq(ZoraCreator1155Impl(payable(deterministicAddress)).balanceOf(collector, tokenId), 1);
    }

    function test_onlyOwnerCanUpgrade() external {
        // try to upgrade as non-owner
        ZoraCreator1155PremintExecutorImpl newImplementation = new ZoraCreator1155PremintExecutorImpl(factoryAtProxy);

        vm.expectRevert(IOwnable2StepUpgradeable.ONLY_OWNER.selector);
        vm.prank(creator);
        preminterAtProxy.upgradeTo(address(newImplementation));
    }

    /// giving this a contract name so that it can be used to fail upgrading preminter contract
    function contractName() public pure returns (string memory) {
        return "Test Contract";
    }

    function test_canOnlyBeUpgradedToContractWithSameName() external {
        // upgrade to bad contract with has wrong name (this contract has mismatched name)
        vm.expectRevert(
            abi.encodeWithSelector(ZoraCreator1155PremintExecutorImpl.UpgradeToMismatchedContractName.selector, preminterAtProxy.contractName(), contractName())
        );
        vm.prank(owner);
        preminterAtProxy.upgradeTo(address(this));

        // upgrade to good contract which has correct name - it shouldn't revert
        ZoraCreator1155PremintExecutorImpl newImplementation = new ZoraCreator1155PremintExecutorImpl(ZoraCreator1155FactoryImpl(address(factoryProxy)));

        vm.prank(owner);
        preminterAtProxy.upgradeTo(address(newImplementation));
    }

    // Failing CI
    // function test_canExecutePremint_onOlderVersionOf1155() external {
    //     vm.createSelectFork("zora", 5_000_000);

    //     // 1. execute premint using older version of proxy, this will create 1155 contract using the legacy interface
    //     address preminterProxy = 0x7777773606e7e46C8Ba8B98C08f5cD218e31d340;
    //     address upgradeGate = 0xbC50029836A59A4E5e1Bb8988272F46ebA0F9900;
    //     // get premint and factory proxies from forked deployments
    //     ZoraCreator1155PremintExecutorImpl forkedPreminterProxy = ZoraCreator1155PremintExecutorImpl(preminterProxy);
    //     ZoraCreator1155FactoryImpl forkedFactoryAtProxy = ZoraCreator1155FactoryImpl(address(forkedPreminterProxy.zora1155Factory()));
    //     IMinter1155 fixedPriceMinter = forkedFactoryAtProxy.fixedPriceMinter();

    //     // build and sign v1 premint config
    //     ContractCreationConfig memory contractConfig = Zora1155PremintFixtures.makeDefaultContractCreationConfig(creator);
    //     address deterministicAddress = forkedPreminterProxy.getContractAddress(contractConfig);
    //     PremintConfig memory premintConfig = Zora1155PremintFixtures.makeDefaultV1PremintConfig(fixedPriceMinter, creator);

    //     bytes memory signature = _signPremint(ZoraCreator1155Attribution.hashPremint(premintConfig), PremintEncoding.HASHED_VERSION_1, deterministicAddress);

    //     // create 1155 contract via premint, using legacy interface
    //     uint256 quantityToMint = 1;

    //     uint256 mintFeeAmount = 0.000777 ether;

    //     vm.deal(collector, mintFeeAmount);
    //     vm.prank(collector);

    //     uint256 tokenId = IRemovedZoraCreator1155PremintExecutorFunctions(address(forkedPreminterProxy)).premint{value: mintFeeAmount}(
    //         contractConfig,
    //         premintConfig,
    //         signature,
    //         quantityToMint,
    //         "yo"
    //     );

    //     // sanity check, make sure the token was minted
    //     assertEq(tokenId, 1);

    //     // 2. upgrade premint executor and factory to current version
    //     // create new factory proxy implementation
    //     (, , ZoraCreator1155FactoryImpl newFactoryVersion) = Zora1155FactoryFixtures.setupNew1155AndFactory(zora, IUpgradeGate(upgradeGate), fixedPriceMinter);

    //     // upgrade factory proxy
    //     address upgradeOwner = forkedPreminterProxy.owner();
    //     vm.prank(upgradeOwner);
    //     forkedFactoryAtProxy.upgradeTo(address(newFactoryVersion));
    //     // upgrade preminter
    //     ZoraCreator1155PremintExecutorImpl newImplementation = new ZoraCreator1155PremintExecutorImpl(forkedFactoryAtProxy);
    //     vm.prank(upgradeOwner);
    //     forkedPreminterProxy.upgradeTo(address(newImplementation));

    //     // 3. get mint fee - it should be the same as it was before
    //     assertEq(mintFeeAmount, forkedPreminterProxy.mintFee(deterministicAddress));

    //     // 3. create new premint on old version of contract using new version of preminter
    //     uint32 existingUid = premintConfig.uid;
    //     premintConfig = Zora1155PremintFixtures.makeDefaultV1PremintConfig(fixedPriceMinter, creator);
    //     premintConfig.uid = existingUid + 1;
    //     signature = _signPremint(ZoraCreator1155Attribution.hashPremint(premintConfig), PremintEncoding.HASHED_VERSION_1, deterministicAddress);

    //     mintFeeAmount = forkedPreminterProxy.mintFee(deterministicAddress);

    //     // execute the premint
    //     vm.deal(collector, mintFeeAmount);
    //     vm.prank(collector);
    //     // now premint using the new method - it should still work
    //     tokenId = forkedPreminterProxy.premintV1{value: mintFeeAmount}(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments).tokenId;

    //     // sanity check, make sure token was minted and has a new token id
    //     assertEq(tokenId, 2);
    // }

    function test_premintExecutor_callsOldMintWithRewards_ifNewMintDoesntExist() external {
        vm.createSelectFork("zora_sepolia", 1_910_812);

        // this test starts from the previously deployed version of premint executor, then:
        // creates an erc1155 via premint.
        // upgrades premint executor to latest version.
        // tries calling preming again with that existing contract.  Since the existing contract doesnt have the new mint function,
        // it should fallback to call the old mintWithRewards

        // 1. execute premint using older version of proxy, this will create 1155 contract using the legacy interface
        address preminterProxy = 0x7777773606e7e46C8Ba8B98C08f5cD218e31d340;
        address upgradeGate = 0xbC50029836A59A4E5e1Bb8988272F46ebA0F9900;
        // get premint and factory proxies from forked deployments
        ZoraCreator1155PremintExecutorImpl forkedPreminterProxy = ZoraCreator1155PremintExecutorImpl(preminterProxy);
        ZoraCreator1155FactoryImpl forkedFactoryAtProxy = ZoraCreator1155FactoryImpl(address(forkedPreminterProxy.zora1155Factory()));
        IMinter1155 fixedPriceMinter = forkedFactoryAtProxy.fixedPriceMinter();

        // build and sign v1 premint config
        ContractCreationConfig memory contractConfig = Zora1155PremintFixtures.makeDefaultContractCreationConfig(creator);
        address deterministicAddress = forkedPreminterProxy.getContractAddress(contractConfig);
        PremintConfig memory premintConfig = Zora1155PremintFixtures.makeDefaultV1PremintConfig(fixedPriceMinter, creator);

        bytes memory signature = _signPremint(ZoraCreator1155Attribution.hashPremint(premintConfig), PremintEncoding.HASHED_VERSION_1, deterministicAddress);

        // create 1155 contract via premint, using legacy interface
        uint256 quantityToMint = 1;

        uint256 mintFeeAmount = forkedPreminterProxy.mintFee(deterministicAddress);

        vm.deal(collector, mintFeeAmount);
        vm.prank(collector);

        uint256 tokenId = IRemovedZoraCreator1155PremintExecutorFunctions(address(forkedPreminterProxy)).premint{value: mintFeeAmount}(
            contractConfig,
            premintConfig,
            signature,
            quantityToMint,
            "yo"
        );

        // sanity check, make sure the token was minted
        assertEq(tokenId, 1);

        // 2. upgrade premint executor and factory to current version
        // create new factory proxy implementation
        (, , ZoraCreator1155FactoryImpl newFactoryVersion) = Zora1155FactoryFixtures.setupNew1155AndFactory(zora, IUpgradeGate(upgradeGate), fixedPriceMinter);

        // upgrade factory proxy
        address upgradeOwner = forkedPreminterProxy.owner();
        vm.prank(upgradeOwner);
        forkedFactoryAtProxy.upgradeTo(address(newFactoryVersion));
        // upgrade preminter
        ZoraCreator1155PremintExecutorImpl newImplementation = new ZoraCreator1155PremintExecutorImpl(forkedFactoryAtProxy);
        vm.prank(upgradeOwner);
        forkedPreminterProxy.upgradeTo(address(newImplementation));

        // 3. create premint on old proxy using new version of preminter
        // execute the premint - get the updated mint fee amount
        mintFeeAmount = forkedPreminterProxy.mintFee(deterministicAddress);
        vm.deal(collector, mintFeeAmount);
        vm.prank(collector);
        // now premint - it should still be able to mint on the old version of the contract, even though new method is not there.
        defaultMintArguments.mintRewardsRecipients = new address[](1);
        address mintReferral = makeAddr("referral");
        defaultMintArguments.mintRewardsRecipients[0] = mintReferral;
        forkedPreminterProxy.premintV1{value: mintFeeAmount}(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments);

        // have mint referral withdraw - it should pass
        vm.prank(mintReferral);
        IProtocolRewards(0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B).withdraw(mintReferral, 0.000111 ether * quantityToMint);
    }

    function test_premintV2_canWorkWithOldInterface() external {
        vm.createSelectFork("zora_sepolia", 4982793);

        // 1. execute premint using currently deployed version of proxy, this will create 1155 contract using the legacy interface
        address preminterProxy = 0x7777773606e7e46C8Ba8B98C08f5cD218e31d340;
        IZoraCreator1155PremintExecutor forkedPreminterProxy = IZoraCreator1155PremintExecutor(preminterProxy);

        // build and sign v2 premint config
        ContractCreationConfig memory contractConfig = Zora1155PremintFixtures.makeDefaultContractCreationConfig(creator);
        contractConfig.contractAdmin = creator;
        contractConfig.contractURI = "ipfs://someurl";
        address deterministicAddress = forkedPreminterProxy.getContractAddress(contractConfig);

        assertEq(deterministicAddress.code.length, 0);

        IMinter1155 fixedPriceMinter = ZoraCreator1155FactoryImpl(address(forkedPreminterProxy.zora1155Factory())).fixedPriceMinter();
        PremintConfigV2 memory premintConfig = PremintConfigV2({
            tokenConfig: Zora1155PremintFixtures.makeTokenCreationConfigV2WithCreateReferral(fixedPriceMinter, address(0), makeAddr("creator")),
            uid: 100,
            version: 0,
            deleted: false
        });

        bytes memory signature = _signPremint(ZoraCreator1155Attribution.hashPremint(premintConfig), PremintEncoding.HASHED_VERSION_2, deterministicAddress);

        // create 1155 contract via premint, using legacy interface
        uint256 quantityToMint = 1;

        uint256 mintFeeAmount = forkedPreminterProxy.mintFee(deterministicAddress);

        vm.deal(collector, mintFeeAmount);
        vm.prank(collector);

        forkedPreminterProxy.premintV2{value: mintFeeAmount}(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments);

        // 2. upgrade to current version of preminter
        // first upgrade 1155 factory to current version
        (, , ZoraCreator1155FactoryImpl newFactoryVersion) = Zora1155FactoryFixtures.setupNew1155AndFactory(
            zora,
            IUpgradeGate(address(0x1234)),
            fixedPriceMinter
        );
        ZoraCreator1155FactoryImpl factory = ZoraCreator1155FactoryImpl(address(forkedPreminterProxy.zora1155Factory()));
        vm.prank(factory.owner());
        factory.upgradeTo(address(newFactoryVersion));
        // now contract has been created; upgrade to latest version of premint executor
        ZoraCreator1155PremintExecutorImpl newVersion = new ZoraCreator1155PremintExecutorImpl(forkedPreminterProxy.zora1155Factory());

        vm.prank(forkedPreminterProxy.owner());
        ZoraCreator1155PremintExecutorImpl(address(forkedPreminterProxy)).upgradeTo(address(newVersion));

        // 2. create premint using upgraded impl

        premintConfig.uid = 101;
        signature = _signPremint(ZoraCreator1155Attribution.hashPremint(premintConfig), PremintEncoding.HASHED_VERSION_2, deterministicAddress);

        mintFeeAmount = forkedPreminterProxy.mintFee(deterministicAddress);

        // it should succeed
        ZoraCreator1155PremintExecutorImpl(address(forkedPreminterProxy)).premintV2{value: mintFeeAmount}(
            contractConfig,
            premintConfig,
            signature,
            quantityToMint,
            defaultMintArguments
        );

        // 3. create premint on new contract
        contractConfig.contractURI = "https://zora.co/555555";

        deterministicAddress = forkedPreminterProxy.getContractAddress(contractConfig);

        signature = _signPremint(ZoraCreator1155Attribution.hashPremint(premintConfig), PremintEncoding.HASHED_VERSION_2, deterministicAddress);

        mintFeeAmount = forkedPreminterProxy.mintFee(deterministicAddress);

        // it should succeed
        ZoraCreator1155PremintExecutorImpl(address(forkedPreminterProxy)).premintV2{value: mintFeeAmount}(
            contractConfig,
            premintConfig,
            signature,
            quantityToMint,
            defaultMintArguments
        );
    }

    function _signPremint(bytes32 structHash, bytes32 premintVersion, address contractAddress) private view returns (bytes memory signature) {
        // sign the premint
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(structHash, contractAddress, premintVersion, block.chainid);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(creatorPrivateKey, digest);

        return abi.encodePacked(r, s, v);
    }
}
