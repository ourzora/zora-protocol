// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {Zora1155FactoryFixtures} from "../fixtures/Zora1155FactoryFixtures.sol";
import {ProtocolRewards} from "@zoralabs/protocol-rewards/src/ProtocolRewards.sol";

import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155} from "../../src/proxies/Zora1155.sol";
import {IZoraCreator1155Errors} from "../../src/interfaces/IZoraCreator1155Errors.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {IMinterErrors} from "../../src/interfaces/IMinterErrors.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {Zora1155Factory} from "../../src/proxies/Zora1155Factory.sol";
import {ZoraCreator1155FactoryImpl} from "../../src/factory/ZoraCreator1155FactoryImpl.sol";
import {ZoraCreator1155PremintExecutorImpl} from "../../src/delegation/ZoraCreator1155PremintExecutorImpl.sol";
import {IZoraCreator1155PremintExecutor} from "../../src/interfaces/IZoraCreator1155PremintExecutor.sol";
import {ZoraCreator1155Attribution, PremintEncoding} from "../../src/delegation/ZoraCreator1155Attribution.sol";
import {ContractCreationConfig, ContractWithAdditionalAdminsCreationConfig, TokenCreationConfig, TokenCreationConfigV2, PremintConfigV2, PremintConfig, MintArguments, PremintConfigEncoded} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {UUPSUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ProxyShim} from "../../src/utils/ProxyShim.sol";
import {IMinterErrors} from "../../src/interfaces/IMinterErrors.sol";
import {ZoraCreator1155PremintExecutorImplLib} from "../../src/delegation/ZoraCreator1155PremintExecutorImplLib.sol";
import {Zora1155PremintFixtures} from "../fixtures/Zora1155PremintFixtures.sol";
import {RewardSplits} from "@zoralabs/protocol-rewards/src/abstract/RewardSplits.sol";

contract ZoraCreator1155PreminterTest is Test {
    uint256 internal constant CONTRACT_BASE_ID = 0;
    uint256 internal constant PERMISSION_BIT_MINTER = 2 ** 2;

    ZoraCreator1155PremintExecutorImpl internal preminter;
    Zora1155Factory factoryProxy;
    ZoraCreator1155FactoryImpl factory;

    ICreatorRoyaltiesControl.RoyaltyConfiguration internal defaultRoyaltyConfig;
    uint256 internal mintFeeAmount = 0.000111 ether;
    uint256 initialTokenId = 777;

    // setup contract config
    uint256 internal creatorPrivateKey;
    address internal creator;
    address internal zora;
    address internal premintExecutor;
    address internal collector;

    MintArguments defaultMintArguments;
    ProtocolRewards rewards;
    ZoraCreator1155Impl zoraCreator1155Impl;

    event PremintedV2(
        address indexed contractAddress,
        uint256 indexed tokenId,
        bool indexed createdNewContract,
        uint32 uid,
        address minter,
        uint256 quantityMinted
    );

    function setUp() external {
        (creator, creatorPrivateKey) = makeAddrAndKey("creator");
        zora = makeAddr("zora");
        premintExecutor = makeAddr("premintExecutor");
        collector = makeAddr("collector");

        vm.startPrank(zora);
        (rewards, zoraCreator1155Impl, , factoryProxy, ) = Zora1155FactoryFixtures.setup1155AndFactoryProxy(zora, zora);
        vm.stopPrank();

        factory = ZoraCreator1155FactoryImpl(address(factoryProxy));

        preminter = new ZoraCreator1155PremintExecutorImpl(factory);

        defaultMintArguments = MintArguments({mintRecipient: premintExecutor, mintComment: "blah", mintRewardsRecipients: new address[](0)});
    }

    function makeDefaultContractCreationConfig() internal view returns (ContractCreationConfig memory) {
        return ContractCreationConfig({contractAdmin: creator, contractName: "blah", contractURI: "blah.contract"});
    }

    function getFixedPriceMinter() internal view returns (IMinter1155) {
        return factory.defaultMinters()[0];
    }

    function makeDefaultPremintConfigV2() internal view returns (PremintConfigV2 memory) {
        return
            PremintConfigV2({
                tokenConfig: Zora1155PremintFixtures.makeDefaultTokenCreationConfigV2(getFixedPriceMinter(), creator),
                uid: 100,
                version: 0,
                deleted: false
            });
    }

    function makeDefaultPremintConfigV1() internal view returns (PremintConfig memory) {
        return Zora1155PremintFixtures.makeDefaultV1PremintConfig(getFixedPriceMinter(), creator);
    }

    function makePremintConfigWithCreateReferral(address createReferral) internal view returns (PremintConfigV2 memory) {
        return
            PremintConfigV2({
                tokenConfig: Zora1155PremintFixtures.makeTokenCreationConfigV2WithCreateReferral(getFixedPriceMinter(), createReferral, creator),
                uid: 100,
                version: 0,
                deleted: false
            });
    }

    function test_v1Signatures_workOnV2Contract() external {
        // 1. Make contract creation params

        // configuration of contract to create
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfig memory premintConfig = Zora1155PremintFixtures.makeDefaultV1PremintConfig({
            fixedPriceMinter: getFixedPriceMinter(),
            royaltyRecipient: creator
        });

        // how many tokens are minted to the executor
        uint256 quantityToMint = 1;
        uint256 chainId = block.chainid;

        // get contract hash, which is unique per contract creation config, and can be used
        // retreive the address created for a contract
        address contractAddress = preminter.getContractAddress(contractConfig);

        // 2. Call smart contract to get digest to sign for creation params.
        bytes32 structHash = ZoraCreator1155Attribution.hashPremint(premintConfig);
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(structHash, contractAddress, PremintEncoding.HASHED_VERSION_1, chainId);

        // 3. Sign the digest
        // create a signature with the digest for the params
        bytes memory signature = _sign(creatorPrivateKey, digest);

        uint256 mintCost = mintFeeAmount * quantityToMint;
        // this account will be used to execute the premint, and should result in a contract being created
        vm.deal(premintExecutor, mintCost);

        // make sure sig is still valid using legacy method
        (bool isValid, , ) = preminter.isValidSignature(contractConfig, premintConfig, signature);
        assertTrue(isValid);

        // now check using new method
        isValid = preminter.isAuthorizedToCreatePremint(creator, contractConfig.contractAdmin, contractAddress);
        assertTrue(isValid);

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.prank(premintExecutor);
        uint256 tokenId = preminter.premintV1{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments).tokenId;

        // get the contract address from the preminter based on the contract hash id.
        IZoraCreator1155 created1155Contract = IZoraCreator1155(contractAddress);
        // get the created contract, and make sure that tokens have been minted to the address
        assertEq(created1155Contract.balanceOf(premintExecutor, tokenId), quantityToMint);
        assertEq(ZoraCreator1155Impl(payable(address(created1155Contract))).delegatedTokenId(premintConfig.uid), tokenId);
    }

    function test_successfullyMintsTokens() external {
        // 1. Make contract creation params

        // configuration of contract to create
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        // how many tokens are minted to the executor
        uint256 quantityToMint = 4;
        uint256 chainId = block.chainid;

        // get contract hash, which is unique per contract creation config, and can be used
        // retreive the address created for a contract
        address contractAddress = preminter.getContractAddress(contractConfig);

        // 2. Call smart contract to get digest to sign for creation params.
        bytes32 structHash = ZoraCreator1155Attribution.hashPremint(premintConfig);
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(structHash, contractAddress, PremintEncoding.HASHED_VERSION_2, chainId);

        // 3. Sign the digest
        // create a signature with the digest for the params
        bytes memory signature = _sign(creatorPrivateKey, digest);

        uint256 mintCost = mintFeeAmount * quantityToMint;
        // this account will be used to execute the premint, and should result in a contract being created
        vm.deal(premintExecutor, mintCost);

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.prank(premintExecutor);
        uint256 tokenId = preminter.premintV2{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments).tokenId;

        // get the contract address from the preminter based on the contract hash id.
        IZoraCreator1155 created1155Contract = IZoraCreator1155(contractAddress);

        // get the created contract, and make sure that tokens have been minted to the address
        assertEq(created1155Contract.balanceOf(premintExecutor, tokenId), quantityToMint);

        // alter the token creation config, create a new signature with the existing
        // contract config and new token config
        premintConfig.tokenConfig.tokenURI = "blah2.token";
        premintConfig.uid++;

        structHash = ZoraCreator1155Attribution.hashPremint(premintConfig);
        digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(structHash, contractAddress, PremintEncoding.HASHED_VERSION_2, chainId);
        signature = _sign(creatorPrivateKey, digest);

        vm.deal(premintExecutor, mintCost);

        // premint with new token config and signature
        vm.prank(premintExecutor);
        tokenId = preminter.premintV2{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments).tokenId;

        // a new token shoudl have been created, with x tokens minted to the executor, on the same contract address
        // as before since the contract config didnt change
        assertEq(created1155Contract.balanceOf(premintExecutor, tokenId), quantityToMint);
    }

    function test_createsContractWithoutMinting() external {
        // 1. Make contract creation params

        // configuration of contract to create
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        // how many tokens are minted to the executor
        uint256 chainId = block.chainid;

        // get contract hash, which is unique per contract creation config, and can be used
        // retreive the address created for a contract
        address contractAddress = preminter.getContractAddress(contractConfig);

        // 2. Call smart contract to get digest to sign for creation params.
        bytes32 structHash = ZoraCreator1155Attribution.hashPremint(premintConfig);
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(structHash, contractAddress, PremintEncoding.HASHED_VERSION_2, chainId);

        // 3. Sign the digest
        // create a signature with the digest for the params
        bytes memory signature = _sign(creatorPrivateKey, digest);

        uint256 quantityToMint = 0;

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.prank(premintExecutor);
        uint256 tokenId = preminter.premintV2(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments).tokenId;

        // get the contract address from the preminter based on the contract hash id.
        IZoraCreator1155 created1155Contract = IZoraCreator1155(contractAddress);

        // get the created contract, and make sure that tokens have been minted to the address
        assertEq(created1155Contract.balanceOf(premintExecutor, tokenId), 0);

        assertEq(ZoraCreator1155Impl(payable(contractAddress)).firstMinters(tokenId), address(premintExecutor));
    }

    event CreatorAttribution(bytes32 structHash, string domainName, string version, address creator, bytes signature);

    function test_premintV1_emitsCreatorAttribution_fromErc1155Contract() external {
        // build a premint
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfig memory premintConfig = makeDefaultPremintConfigV1();

        // sign and execute premint
        uint256 chainId = block.chainid;

        address deterministicAddress = preminter.getContractAddress(contractConfig);
        bytes32 structHash = ZoraCreator1155Attribution.hashPremint(premintConfig);
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(structHash, deterministicAddress, PremintEncoding.HASHED_VERSION_1, chainId);
        bytes memory signature = _sign(creatorPrivateKey, digest);

        uint256 quantityToMint = 4;
        uint256 mintCost = mintFeeAmount * quantityToMint;
        // this account will be used to execute the premint, and should result in a contract being created
        vm.deal(collector, mintCost);

        vm.prank(collector);

        // verify CreatorAttribution was emitted from the erc1155 contract
        vm.expectEmit(true, true, true, true, deterministicAddress);
        emit CreatorAttribution(structHash, ZoraCreator1155Attribution.NAME, PremintEncoding.VERSION_1, creator, signature);

        // create contract and token via premint
        preminter.premintV1{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments);
    }

    function test_premintV2_emitsCreatorAttribution_fromErc1155Contract() external {
        // build a premint
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        // sign and execute premint
        uint256 chainId = block.chainid;

        address deterministicAddress = preminter.getContractAddress(contractConfig);
        bytes32 structHash = ZoraCreator1155Attribution.hashPremint(premintConfig);
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(structHash, deterministicAddress, PremintEncoding.HASHED_VERSION_2, chainId);
        bytes memory signature = _sign(creatorPrivateKey, digest);

        uint256 quantityToMint = 4;
        uint256 mintCost = mintFeeAmount * quantityToMint;
        // this account will be used to execute the premint, and should result in a contract being created
        vm.deal(collector, mintCost);

        vm.prank(collector);

        // verify CreatorAttribution was emitted from the erc1155 contract
        vm.expectEmit(true, true, true, true, deterministicAddress);
        emit CreatorAttribution(structHash, ZoraCreator1155Attribution.NAME, PremintEncoding.VERSION_2, creator, signature);

        // create contract and token via premint
        preminter.premintV2{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments);
    }

    function preminterCanMintTokens() internal {
        // we are for now upgrading to correct preminter impl

        // configuration of contract to create
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        // how many tokens are minted to the executor
        uint256 quantityToMint = 4;
        uint256 chainId = block.chainid;

        console.log("loading preminter");

        address contractAddress = preminter.getContractAddress(contractConfig);

        // 2. Call smart contract to get digest to sign for creation params.
        bytes32 structHash = ZoraCreator1155Attribution.hashPremint(premintConfig);
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(structHash, contractAddress, PremintEncoding.HASHED_VERSION_2, chainId);

        // 3. Sign the digest
        // create a signature with the digest for the params
        bytes memory signature = _sign(creatorPrivateKey, digest);

        // this account will be used to execute the premint, and should result in a contract being created
        premintExecutor = vm.addr(701);
        uint256 mintCost = quantityToMint * 0.000111 ether;
        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.deal(premintExecutor, mintCost);
        vm.prank(premintExecutor);
        uint256 tokenId = preminter.premintV2{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments).tokenId;

        // get the contract address from the preminter based on the contract hash id.
        IZoraCreator1155 created1155Contract = IZoraCreator1155(contractAddress);

        // console.log("getting balance");
        // get the created contract, and make sure that tokens have been minted to the address
        uint256 balance = created1155Contract.balanceOf(premintExecutor, tokenId);

        assertEq(balance, quantityToMint, "balance");
    }

    function test_paidMint_creatorGetsPaidMintFunds() external {
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        address payoutRecipient = makeAddr("payoutRecipient");

        premintConfig.tokenConfig.pricePerToken = 1 ether;
        premintConfig.tokenConfig.payoutRecipient = payoutRecipient;

        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();

        uint256 quantityToMint = 4;

        _signAndExecutePremint(contractConfig, premintConfig, creatorPrivateKey, block.chainid, premintExecutor, quantityToMint, "blah");

        assertEq(payoutRecipient.balance, quantityToMint * premintConfig.tokenConfig.pricePerToken);
    }

    function test_signatureForSameContractandUid_shouldMintExistingToken() external {
        // 1. Make contract creation params

        // configuration of contract to create
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        // how many tokens are minted to the executor
        uint256 quantityToMint = 2;
        uint256 chainId = block.chainid;
        string memory comment = "I love it";

        address contractAddress = preminter.getContractAddress(contractConfig);
        IZoraCreator1155 created1155Contract = IZoraCreator1155(contractAddress);

        uint256 firstTokenId = _signAndExecutePremint(contractConfig, premintConfig, creatorPrivateKey, chainId, premintExecutor, quantityToMint, comment);

        // create a sig for another token with same uid, it should mint tokens for the uid's original token
        premintConfig.tokenConfig.tokenURI = "blah2.token";
        bytes memory signature = _signPremint(contractAddress, premintConfig, creatorPrivateKey, chainId);

        uint256 mintCost = mintFeeAmount * quantityToMint;
        vm.deal(collector, mintCost);

        uint256 nextTokenId;

        uint256 beforeTokenBalance = created1155Contract.balanceOf(defaultMintArguments.mintRecipient, firstTokenId);

        vm.startPrank(collector);
        // premint with new token config and signature, but same uid - it should mint tokens for the first token
        nextTokenId = preminter.premintV2{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments).tokenId;

        assertEq(nextTokenId, firstTokenId);
        assertEq(
            created1155Contract.balanceOf(defaultMintArguments.mintRecipient, firstTokenId) - beforeTokenBalance,
            quantityToMint,
            "balance after first mint"
        );

        // change the version, it should still point to the first token
        premintConfig.version++;
        signature = _signPremint(contractAddress, premintConfig, creatorPrivateKey, chainId);

        vm.deal(collector, mintCost);

        // premint with new token config and signature - it should mint tokens for the first token
        nextTokenId = preminter.premintV2{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments).tokenId;
        vm.stopPrank();

        assertEq(nextTokenId, firstTokenId);
        assertEq(
            created1155Contract.balanceOf(defaultMintArguments.mintRecipient, firstTokenId) - beforeTokenBalance,
            quantityToMint * 2,
            "balance after second mint"
        );
    }

    function test_mintReferral_getsMintReferralReward() public {
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        address mintReferral = makeAddr("mintReferral");

        address minter = makeAddr("minter");

        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();

        uint256 quantityToMint = 4;

        bytes memory signature = _signPremint(preminter.getContractAddress(contractConfig), premintConfig, creatorPrivateKey, block.chainid);

        address[] memory mintRewardsRecipients = new address[](1);
        mintRewardsRecipients[0] = mintReferral;

        MintArguments memory mintArguments = MintArguments({mintRecipient: minter, mintComment: "", mintRewardsRecipients: mintRewardsRecipients});

        uint256 mintCost = (mintFeeAmount + premintConfig.tokenConfig.pricePerToken) * quantityToMint;

        vm.deal(minter, mintCost);
        vm.prank(minter);
        preminter.premintV2{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, mintArguments);

        // now get balance of mintReferral in ProtocolRewards - it should be mint referral reward amount * quantityToMint
        uint256 mintReferralReward = 14_228500;
        uint256 referralReward = (mintCost * mintReferralReward) / 10_0000000;

        assertEq(rewards.balanceOf(mintReferral), referralReward);

        vm.prank(mintReferral);
        rewards.withdraw(mintReferral, referralReward);

        assertEq(mintReferral.balance, referralReward);
    }

    function testCreateTokenPerUid() public {
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        uint256 quantityToMint = 2;
        uint256 chainId = block.chainid;
        string memory comment = "I love it";

        address contractAddress = preminter.getContractAddress(contractConfig);

        uint256 firstTokenId = _signAndExecutePremint(contractConfig, premintConfig, creatorPrivateKey, chainId, premintExecutor, quantityToMint, comment);

        // creator signs a new uid, it should create a new token
        premintConfig.uid++;
        bytes memory signature = _signPremint(contractAddress, premintConfig, creatorPrivateKey, chainId);

        uint256 mintCost = mintFeeAmount * quantityToMint;
        vm.deal(collector, mintCost);

        vm.startPrank(collector);
        // premint with new token config and signature, but same uid - it should mint tokens for the first token
        uint256 nextTokenId = preminter.premintV2{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments).tokenId;

        assertEq(firstTokenId, 1);
        assertEq(nextTokenId, 2);
    }

    function test_deleted_preventsTokenFromBeingMinted() external {
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        premintConfig.deleted = true;
        uint chainId = block.chainid;
        uint256 quantityToMint = 2;

        address contractAddress = preminter.getContractAddress(contractConfig);

        // 2. Call smart contract to get digest to sign for creation params.
        bytes memory signature = _signPremint(contractAddress, premintConfig, creatorPrivateKey, chainId);

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.expectRevert(IZoraCreator1155Errors.PremintDeleted.selector);
        vm.prank(premintExecutor);
        uint256 newTokenId = preminter.premintV2(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments).tokenId;

        assertEq(newTokenId, 0, "tokenId");

        // make sure no contract was created
        assertEq(contractAddress.code.length, 0, "contract has been deployed");
    }

    function test_emitsPremint_whenNewContract() external {
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();
        address contractAddress = preminter.getContractAddress(contractConfig);

        // how many tokens are minted to the executor
        uint256 quantityToMint = 4;
        uint256 chainId = block.chainid;

        // Sign the premint
        bytes memory signature = _signPremint(contractAddress, premintConfig, creatorPrivateKey, chainId);

        uint256 expectedTokenId = 1;

        uint256 mintCost = mintFeeAmount * quantityToMint;
        // this account will be used to execute the premint, and should result in a contract being created
        vm.deal(premintExecutor, mintCost);

        vm.startPrank(premintExecutor);

        bool createdNewContract = true;
        vm.expectEmit(true, true, true, true);
        emit PremintedV2(contractAddress, expectedTokenId, createdNewContract, premintConfig.uid, premintExecutor, quantityToMint);
        preminter.premintV2{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments);
    }

    function test_onlyOwner_hasAdminRights_onCreatedToken() public {
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        // how many tokens are minted to the executor
        uint256 quantityToMint = 4;
        uint256 chainId = block.chainid;

        string memory comment = "I love it";

        address createdContractAddress = preminter.getContractAddress(contractConfig);

        uint256 newTokenId = _signAndExecutePremint(contractConfig, premintConfig, creatorPrivateKey, chainId, premintExecutor, quantityToMint, comment);

        // get the contract address from the preminter based on the contract hash id.
        IZoraCreator1155 created1155Contract = IZoraCreator1155(createdContractAddress);

        ZoraCreatorFixedPriceSaleStrategy.SalesConfig memory newSalesConfig = ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
            pricePerToken: 5 ether,
            saleStart: 0,
            saleEnd: 0,
            maxTokensPerAddress: 5,
            fundsRecipient: creator
        });

        IMinter1155 fixedPrice = factory.fixedPriceMinter();

        // have the premint contract try to set the sales config - it should revert with
        // the expected UserMissingRole error
        vm.expectRevert(
            abi.encodeWithSelector(
                IZoraCreator1155Errors.UserMissingRoleForToken.selector,
                address(preminter),
                newTokenId,
                ZoraCreator1155Impl(payable(address(created1155Contract))).PERMISSION_BIT_SALES()
            )
        );
        vm.prank(address(preminter));
        created1155Contract.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(ZoraCreatorFixedPriceSaleStrategy.setSale.selector, newTokenId, newSalesConfig)
        );

        // have admin/creator try to set the sales config - it should succeed
        vm.prank(creator);
        created1155Contract.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(ZoraCreatorFixedPriceSaleStrategy.setSale.selector, newTokenId, newSalesConfig)
        );

        // have the premint contract try to set royalties config - it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IZoraCreator1155Errors.UserMissingRoleForToken.selector,
                address(preminter),
                newTokenId,
                ZoraCreator1155Impl(payable(address(created1155Contract))).PERMISSION_BIT_FUNDS_MANAGER()
            )
        );
        vm.prank(address(preminter));
        created1155Contract.updateRoyaltiesForToken(newTokenId, defaultRoyaltyConfig);

        // have admin/creator try to set royalties config - it should succeed
        vm.prank(creator);
        created1155Contract.updateRoyaltiesForToken(newTokenId, defaultRoyaltyConfig);
    }

    function test_premintStatus_getsStatus() external {
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        // how many tokens are minted to the executor
        uint256 quantityToMint = 4;
        uint256 chainId = block.chainid;
        string memory comment = "I love it";

        uint32 firstUid = premintConfig.uid;
        uint32 secondUid = firstUid + 1;

        ContractCreationConfig memory firstContractConfig = makeDefaultContractCreationConfig();
        ContractCreationConfig memory secondContractConfig = ContractCreationConfig(
            firstContractConfig.contractAdmin,
            firstContractConfig.contractURI,
            string.concat(firstContractConfig.contractName, "4")
        );

        address firstContractAddress = preminter.getContractAddress(firstContractConfig);
        uint256 tokenId = _signAndExecutePremint(firstContractConfig, premintConfig, creatorPrivateKey, chainId, premintExecutor, quantityToMint, comment);

        assertEq(IZoraCreator1155(firstContractAddress).balanceOf(premintExecutor, tokenId), quantityToMint);

        premintConfig.uid = secondUid;
        tokenId = _signAndExecutePremint(firstContractConfig, premintConfig, creatorPrivateKey, chainId, premintExecutor, quantityToMint, comment);

        assertEq(IZoraCreator1155(firstContractAddress).balanceOf(premintExecutor, tokenId), quantityToMint);

        address secondContractAddress = preminter.getContractAddress(secondContractConfig);
        tokenId = _signAndExecutePremint(secondContractConfig, premintConfig, creatorPrivateKey, chainId, premintExecutor, quantityToMint, comment);

        assertEq(IZoraCreator1155(secondContractAddress).balanceOf(premintExecutor, tokenId), quantityToMint);
    }

    function test_premintCanOnlyBeExecutedAfterStartDate(uint8 startDate, uint8 currentTime) external {
        bool shouldRevert;
        if (startDate == 0) {
            shouldRevert = false;
        } else {
            // should revert if before the start date
            shouldRevert = currentTime < startDate;
        }
        vm.warp(currentTime);

        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();
        premintConfig.tokenConfig.mintStart = startDate;

        uint256 quantityToMint = 4;
        uint256 chainId = block.chainid;

        // get signature for the premint:
        bytes memory signature = _signPremint(preminter.getContractAddress(contractConfig), premintConfig, creatorPrivateKey, chainId);

        if (shouldRevert) {
            vm.expectRevert(IZoraCreator1155Errors.MintNotYetStarted.selector);
        }

        uint256 mintCost = mintFeeAmount * quantityToMint;
        vm.deal(premintExecutor, mintCost);

        vm.prank(premintExecutor);
        preminter.premintV2{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments);
    }

    function test_premintCanOnlyBeExecutedUpToDurationFromFirstMint(uint8 startDate, uint8 duration, uint8 timeOfFirstMint, uint8 timeOfSecondMint) external {
        vm.assume(timeOfFirstMint >= startDate);
        vm.assume(timeOfSecondMint >= timeOfFirstMint);

        bool shouldRevert;
        if (duration == 0) {
            shouldRevert = false;
        } else {
            // should revert if after the duration
            shouldRevert = uint16(timeOfSecondMint) > uint16(timeOfFirstMint) + duration;
        }

        // build a premint with a token that has the given start date and duration
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();
        address contractAddress = preminter.getContractAddress(contractConfig);

        premintConfig.tokenConfig.mintStart = startDate;
        premintConfig.tokenConfig.mintDuration = duration;

        uint256 chainId = block.chainid;

        // get signature for the premint:
        bytes memory signature = _signPremint(contractAddress, premintConfig, creatorPrivateKey, chainId);

        uint256 quantityToMint = 2;
        string memory comment = "I love it";

        uint256 mintCost = mintFeeAmount * quantityToMint;
        vm.deal(premintExecutor, mintCost);

        vm.startPrank(premintExecutor);

        vm.warp(timeOfFirstMint);
        uint256 tokenId = preminter.premintV2{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, defaultMintArguments).tokenId;

        vm.warp(timeOfSecondMint);

        // execute mint directly on the contract - and check make sure it reverts if minted after sale start
        IMinter1155 fixedPriceMinter = factory.defaultMinters()[0];
        if (shouldRevert) {
            vm.expectRevert(IMinterErrors.SaleEnded.selector);
        }

        address[] memory rewardsRecipients = new address[](1);

        vm.deal(premintExecutor, mintCost);
        IZoraCreator1155(contractAddress).mint{value: mintCost}(
            fixedPriceMinter,
            tokenId,
            quantityToMint,
            rewardsRecipients,
            abi.encode(premintExecutor, comment)
        );

        vm.stopPrank();
    }

    function test_premintStatus_getsIfContractHasBeenCreatedAndTokenIdForPremint() external {
        // build a premint
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        // get premint status
        (bool contractCreated, uint256 tokenId) = preminter.premintStatus(preminter.getContractAddress(contractConfig), premintConfig.uid);
        // contract should not be created and token id should be 0
        assertEq(contractCreated, false);
        assertEq(tokenId, 0);

        // sign and execute premint
        uint256 newTokenId = _signAndExecutePremint(contractConfig, premintConfig, creatorPrivateKey, block.chainid, vm.addr(701), 1, "hi");

        // get status
        (contractCreated, tokenId) = preminter.premintStatus(preminter.getContractAddress(contractConfig), premintConfig.uid);
        // contract should be created and token id should be same as one that was created
        assertEq(contractCreated, true);
        assertEq(tokenId, newTokenId);

        // get status for another uid
        (contractCreated, tokenId) = preminter.premintStatus(preminter.getContractAddress(contractConfig), premintConfig.uid + 1);
        // contract should be created and token id should be 0
        assertEq(contractCreated, true);
        assertEq(tokenId, 0);
    }

    function test_premint_whenContractCreated_premintCanOnlyBeExecutedByPermissionBitMinter() external {
        // build a premint
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        address contractAddress = preminter.getContractAddress(contractConfig);

        bool isValidSignature = preminter.isAuthorizedToCreatePremint({
            signer: creator,
            premintContractConfigContractAdmin: contractConfig.contractAdmin,
            contractAddress: contractAddress
        });

        assertTrue(isValidSignature, "creator should be allowed to create premint before contract created");

        _signAndExecutePremint(contractConfig, premintConfig, creatorPrivateKey, block.chainid, premintExecutor, 1, "hi");

        // contract has been created

        // have another creator sign a premint
        uint256 newCreatorPrivateKey = 0xA11CF;
        address newCreator = vm.addr(newCreatorPrivateKey);
        PremintConfigV2 memory premintConfig2 = premintConfig;
        premintConfig2.uid++;

        // have new creator sign a premint, isValidSignature should be false, and premint should revert
        bytes memory newCreatorSignature = _signPremint(contractAddress, premintConfig2, newCreatorPrivateKey, block.chainid);

        // it should not be considered a valid signature
        isValidSignature = preminter.isAuthorizedToCreatePremint({
            signer: newCreator,
            premintContractConfigContractAdmin: contractConfig.contractAdmin,
            contractAddress: contractAddress
        });

        assertFalse(isValidSignature, "alternative creator should not be allowed to create a premint");

        uint256 quantityToMint = 1;
        uint256 mintCost = mintFeeAmount * quantityToMint;
        vm.deal(premintExecutor, mintCost);

        // try to mint, it should revert
        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155Errors.UserMissingRoleForToken.selector, newCreator, CONTRACT_BASE_ID, PERMISSION_BIT_MINTER));
        vm.prank(premintExecutor);
        preminter.premintV2{value: mintCost}(contractConfig, premintConfig2, newCreatorSignature, quantityToMint, defaultMintArguments);

        // now grant the new creator permission to mint
        vm.prank(creator);
        IZoraCreator1155(contractAddress).addPermission(CONTRACT_BASE_ID, newCreator, PERMISSION_BIT_MINTER);

        // should now be considered a valid signature
        isValidSignature = preminter.isAuthorizedToCreatePremint({
            signer: newCreator,
            premintContractConfigContractAdmin: contractConfig.contractAdmin,
            contractAddress: contractAddress
        });
        assertTrue(isValidSignature, "valid signature after granted permission");

        vm.deal(premintExecutor, mintCost);

        // try to mint again, should not revert
        vm.prank(premintExecutor);
        preminter.premintV2{value: mintCost}(contractConfig, premintConfig2, newCreatorSignature, quantityToMint, defaultMintArguments);
    }

    function test_premintVersion_whenCreatedBeforePremint_returnsZero() external {
        vm.createSelectFork("zora", 5_789_193);

        // create preminter on fork
        vm.startPrank(zora);
        (, , , factoryProxy, ) = Zora1155FactoryFixtures.setup1155AndFactoryProxy(zora, zora);
        vm.stopPrank();

        factory = ZoraCreator1155FactoryImpl(address(factoryProxy));

        preminter = new ZoraCreator1155PremintExecutorImpl(factory);

        // this is a known contract deployed from the legacy factory proxy on zora mainnet
        // that does not support getting the uid or premint sig version (it is prior to version 2)
        address erc1155BeforePremint = 0xcACBbee9C2C703274BE026B62860cF56361410f3;
        assertFalse(erc1155BeforePremint.code.length == 0);

        // if contract is not a known 1155 contract that supports getting uid or premint sig version,
        // this should return 0
        assertEq(preminter.supportedPremintSignatureVersions(erc1155BeforePremint).length, 0);
    }

    function test_premintVersion_beforeCreated_returnsAllVersion() external {
        // build a premint
        string[] memory supportedVersions = preminter.supportedPremintSignatureVersions(makeAddr("randomContract"));

        assertEq(supportedVersions.length, 3);
        assertEq(supportedVersions[0], "1");
        assertEq(supportedVersions[1], "2");
        assertEq(supportedVersions[2], "3");
    }

    function test_premintVersion_whenCreated_returnsAllVersion() external {
        // build a premint
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        // sign and execute premint
        address deterministicAddress = preminter.getContractAddress(contractConfig);

        _signAndExecutePremint(contractConfig, premintConfig, creatorPrivateKey, block.chainid, premintExecutor, 1, "hi");

        string[] memory supportedVersions = preminter.supportedPremintSignatureVersions(deterministicAddress);

        assertEq(supportedVersions.length, 3);
        assertEq(supportedVersions[0], "1");
        assertEq(supportedVersions[1], "2");
        assertEq(supportedVersions[2], "3");
    }

    function testPremintWithCreateReferral() public {
        address createReferral = makeAddr("createReferral");

        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfigV2 memory premintConfig = makePremintConfigWithCreateReferral(createReferral);

        uint256 createdTokenId = _signAndExecutePremint(contractConfig, premintConfig, creatorPrivateKey, block.chainid, premintExecutor, 1, "hi");

        ZoraCreator1155Impl createdContract = ZoraCreator1155Impl(payable(preminter.getContractAddress(contractConfig)));

        address storedCreateReferral = createdContract.createReferrals(createdTokenId);

        assertEq(storedCreateReferral, createReferral);
    }

    function test_premintWithNoMintRecipient_reverts() public {
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        address contractAddress = preminter.getContractAddress(contractConfig);

        // sign and execute premint
        bytes memory signature = _signPremint(contractAddress, premintConfig, creatorPrivateKey, block.chainid);

        MintArguments memory mintArguments = MintArguments({mintRecipient: address(0), mintComment: "", mintRewardsRecipients: new address[](0)});

        uint256 quantityToMint = 3;
        uint256 mintCost = mintFeeAmount * quantityToMint;
        address executor = makeAddr("executor");
        vm.deal(executor, mintCost);

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.prank(executor);
        vm.expectRevert(IZoraCreator1155Errors.ERC1155_MINT_TO_ZERO_ADDRESS.selector);

        preminter.premintV2{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, mintArguments).tokenId;
    }

    function _emptyInitData() private pure returns (bytes[] memory response) {
        response = new bytes[](0);
    }

    function test_premintExistingContract_worksOnNonPremintCreatedContracts() public {
        ZoraCreator1155Impl zora1155 = ZoraCreator1155Impl(payable(address(new Zora1155(address(zoraCreator1155Impl)))));

        zora1155.initialize("test", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), payable(creator), _emptyInitData());

        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        bytes memory signature = _signPremint(address(zora1155), premintConfig, creatorPrivateKey, block.chainid);

        uint256 quantityToMint = 3;
        uint256 mintCost = mintFeeAmount * quantityToMint;
        address executor = makeAddr("executor");
        vm.deal(executor, mintCost);

        ContractWithAdditionalAdminsCreationConfig memory emptyContractConfig;

        // now call premintExistingContract
        vm.prank(executor);
        vm.expectEmit(true, true, true, true);
        emit PremintedV2(address(zora1155), 1, false, premintConfig.uid, executor, quantityToMint);
        preminter.premint{value: mintCost}(
            emptyContractConfig,
            address(zora1155),
            PremintEncoding.encodePremint(premintConfig),
            signature,
            quantityToMint,
            defaultMintArguments,
            makeAddr("firstMinter"),
            address(0)
        );

        assertEq(zora1155.balanceOf(defaultMintArguments.mintRecipient, 1), quantityToMint);
    }

    uint256 constant PERMISSION_BIT_ADMIN = 2 ** 1;

    function test_premint_withCollaborators_whenContractOnChain_allowsCollaboratorsToCreatePremint() public {
        // this tests, that when there are collaborators, after a premint is brought onchain,
        // collaborator premints are valid
        (address collaboratorA, uint256 collaboratorPrivateKey) = makeAddrAndKey("collaborator");
        address collaboratorB = makeAddr("collaboratorB");

        address[] memory collaborators = new address[](2);
        collaborators[0] = collaboratorA;
        collaborators[1] = collaboratorB;

        ContractWithAdditionalAdminsCreationConfig memory contractConfig = ContractWithAdditionalAdminsCreationConfig({
            contractAdmin: creator,
            contractName: "blah",
            contractURI: "blah.contract",
            additionalAdmins: collaborators
        });
        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        PremintConfigV2 memory collaboratorPremintConfig = makeDefaultPremintConfigV2();
        collaboratorPremintConfig.uid = premintConfig.uid + 1;

        address contractAddress = preminter.getContractWithAdditionalAdminsAddress(contractConfig);

        // sign and execute premint
        bytes memory creatorPremintSignature = _signPremint(contractAddress, premintConfig, creatorPrivateKey, block.chainid);
        bytes memory collaboratorPremintSignature = _signPremint(contractAddress, collaboratorPremintConfig, collaboratorPrivateKey, block.chainid);

        address executor = makeAddr("executor");
        vm.deal(executor, 100 ether);
        vm.startPrank(executor);

        uint256 quantityToMint = 3;
        uint256 mintCost = mintFeeAmount * quantityToMint;

        // premint using the creators premint - this should create the contract add the collaborators as admins
        preminter.premint{value: mintCost}(
            contractConfig,
            address(0),
            PremintEncoding.encodePremint(premintConfig),
            creatorPremintSignature,
            quantityToMint,
            defaultMintArguments,
            makeAddr("firstMinter"),
            address(0)
        );

        // both collaborators should be added as admins
        assertTrue(IZoraCreator1155(contractAddress).isAdminOrRole(collaboratorA, 0, PERMISSION_BIT_ADMIN));
        assertTrue(IZoraCreator1155(contractAddress).isAdminOrRole(collaboratorB, 0, PERMISSION_BIT_ADMIN));

        // premint against existing contract using the collaborators premint - it should succeed
        uint256 collaboratorTokenId = preminter
        .premint{value: mintCost}(
            contractConfig,
            contractAddress,
            PremintEncoding.encodePremint(collaboratorPremintConfig),
            collaboratorPremintSignature,
            quantityToMint,
            defaultMintArguments,
            makeAddr("firstMinter"),
            address(0)
        ).tokenId;

        assertEq(collaboratorTokenId, 2);
    }

    function test_premint_withCollaborators_beforeContractOnChain_allowsCollaboratorsToCreatePremint() public {
        // this tests, that when there are collaborators, before a premint is brought onchain,
        // collaborator premints are valid
        (address collaboratorA, uint256 collaboratorPrivateKey) = makeAddrAndKey("collaborator");
        address collaboratorB = makeAddr("collaboratorB");

        address[] memory collaborators = new address[](2);
        collaborators[0] = collaboratorA;
        collaborators[1] = collaboratorB;

        ContractWithAdditionalAdminsCreationConfig memory contractConfig = ContractWithAdditionalAdminsCreationConfig({
            contractAdmin: creator,
            contractName: "blah",
            contractURI: "blah.contract",
            additionalAdmins: collaborators
        });

        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        PremintConfigV2 memory collaboratorPremintConfig = makeDefaultPremintConfigV2();
        collaboratorPremintConfig.uid = premintConfig.uid + 1;

        address contractAddress = preminter.getContractWithAdditionalAdminsAddress(contractConfig);

        // sign and execute premint
        bytes memory creatorPremintSignature = _signPremint(contractAddress, premintConfig, creatorPrivateKey, block.chainid);
        bytes memory collaboratorPremintSignature = _signPremint(contractAddress, collaboratorPremintConfig, collaboratorPrivateKey, block.chainid);

        address executor = makeAddr("executor");
        vm.deal(executor, 100 ether);
        vm.startPrank(executor);

        uint256 quantityToMint = 3;
        uint256 mintCost = mintFeeAmount * quantityToMint;

        // premint using the collaborators premint
        preminter.premint{value: mintCost}(
            contractConfig,
            address(0),
            PremintEncoding.encodePremint(collaboratorPremintConfig),
            collaboratorPremintSignature,
            quantityToMint,
            defaultMintArguments,
            makeAddr("firstMinter"),
            address(0)
        );

        // both collaborators should be added as admins
        assertTrue(IZoraCreator1155(contractAddress).isAdminOrRole(creator, 0, PERMISSION_BIT_ADMIN));
        assertTrue(IZoraCreator1155(contractAddress).isAdminOrRole(collaboratorA, 0, PERMISSION_BIT_ADMIN));
        assertTrue(IZoraCreator1155(contractAddress).isAdminOrRole(collaboratorB, 0, PERMISSION_BIT_ADMIN));

        // premint against the existing contract using the original creators premint
        uint256 creatorTokenId = preminter
        .premint{value: mintCost}(
            contractConfig,
            contractAddress,
            PremintEncoding.encodePremint(premintConfig),
            creatorPremintSignature,
            quantityToMint,
            defaultMintArguments,
            makeAddr("firstMinter"),
            address(0)
        ).tokenId;

        assertEq(creatorTokenId, 2);
    }

    function test_isAuthorizedToCreatePremint_worksWithAdditionalCollaborators() external {
        address collaboratorA = makeAddr("collaborator");
        address collaboratorB = makeAddr("collaboratorB");
        address nonCollaborator = makeAddr("nonCollaborator");

        address[] memory additionalAdmins = new address[](2);

        // make collaborator a contract admin
        additionalAdmins[0] = collaboratorA;
        // make collaborator b contract wide minter
        additionalAdmins[1] = collaboratorB;
        // make collaborator c another role - it should not be authorized to create a premint

        ContractWithAdditionalAdminsCreationConfig memory contractConfig = ContractWithAdditionalAdminsCreationConfig({
            contractAdmin: creator,
            contractName: "blah",
            contractURI: "blah.contract",
            additionalAdmins: additionalAdmins
        });

        address contractAddress = preminter.getContractWithAdditionalAdminsAddress(contractConfig);

        // creator should be able to create a premint
        assertTrue(
            preminter.isAuthorizedToCreatePremintWithAdditionalAdmins({
                signer: creator,
                premintContractConfigContractAdmin: contractConfig.contractAdmin,
                contractAddress: contractAddress,
                additionalAdmins: additionalAdmins
            }),
            "creator"
        );

        // collaborator a should be able to create a premint since its a contract wide admin
        assertTrue(
            preminter.isAuthorizedToCreatePremintWithAdditionalAdmins({
                signer: collaboratorA,
                premintContractConfigContractAdmin: contractConfig.contractAdmin,
                contractAddress: contractAddress,
                additionalAdmins: additionalAdmins
            }),
            "collaborator a"
        );

        // collaborator b should be able to create a premint since its a contract wide minter
        assertTrue(
            preminter.isAuthorizedToCreatePremintWithAdditionalAdmins({
                signer: collaboratorB,
                premintContractConfigContractAdmin: contractConfig.contractAdmin,
                contractAddress: contractAddress,
                additionalAdmins: additionalAdmins
            }),
            "collaborator b"
        );

        // collaborator c should not be able to create a premint since it has a random role that is not a contract admin
        assertFalse(
            preminter.isAuthorizedToCreatePremintWithAdditionalAdmins({
                signer: nonCollaborator,
                premintContractConfigContractAdmin: contractConfig.contractAdmin,
                contractAddress: contractAddress,
                additionalAdmins: additionalAdmins
            }),
            "collaborator c"
        );
    }

    function test_mintFee_onOldContracts_returnsExistingMintFee() external {
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();

        address contractAddress = preminter.getContractAddress(contractConfig);

        uint256 mintFee = preminter.mintFee(contractAddress);

        assertEq(mintFee, 0.000111 ether);
    }

    function test_mintFee_onNewContracts_returnsNewMintFee() external {
        ContractCreationConfig memory contractConfig = makeDefaultContractCreationConfig();

        PremintConfigV2 memory premintConfig = makeDefaultPremintConfigV2();

        _signAndExecutePremint(contractConfig, premintConfig, creatorPrivateKey, block.chainid, premintExecutor, 1, "hi");

        // sign and execute premint
        address contractAddress = preminter.getContractAddress(contractConfig);

        uint256 mintFee = preminter.mintFee(contractAddress);

        assertEq(mintFee, mintFeeAmount);
    }

    function _signAndExecutePremint(
        ContractCreationConfig memory contractConfig,
        PremintConfigV2 memory premintConfig,
        uint256 privateKey,
        uint256 chainId,
        address executor,
        uint256 quantityToMint,
        string memory comment
    ) private returns (uint256 newTokenId) {
        bytes memory signature = _signPremint(preminter.getContractAddress(contractConfig), premintConfig, privateKey, chainId);

        MintArguments memory mintArguments = MintArguments({mintRecipient: executor, mintComment: comment, mintRewardsRecipients: new address[](0)});

        uint256 mintCost = (mintFeeAmount + premintConfig.tokenConfig.pricePerToken) * quantityToMint;
        vm.deal(executor, mintCost);

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.prank(executor);
        newTokenId = preminter.premintV2{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, mintArguments).tokenId;
    }

    function _signPremint(
        address contractAddress,
        PremintConfigV2 memory premintConfig,
        uint256 privateKey,
        uint256 chainId
    ) private pure returns (bytes memory signature) {
        bytes32 structHash = ZoraCreator1155Attribution.hashPremint(premintConfig);
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(structHash, contractAddress, PremintEncoding.HASHED_VERSION_2, chainId);

        // create a signature with the digest for the params
        signature = _sign(privateKey, digest);
    }

    function _sign(uint256 privateKey, bytes32 digest) private pure returns (bytes memory) {
        // sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // combine into a single bytes array
        return abi.encodePacked(r, s, v);
    }
}
