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
import {ContractWithAdditionalAdminsCreationConfig, TokenCreationConfigV2, PremintConfigV2, MintArguments, PremintResult} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {UUPSUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ProxyShim} from "../../src/utils/ProxyShim.sol";
import {IMinterErrors} from "../../src/interfaces/IMinterErrors.sol";
import {ZoraCreator1155PremintExecutorImplLib} from "../../src/delegation/ZoraCreator1155PremintExecutorImplLib.sol";
import {Zora1155PremintFixtures} from "../fixtures/Zora1155PremintFixtures.sol";
import {RewardSplits} from "@zoralabs/protocol-rewards/src/abstract/RewardSplits.sol";
import {ECDSAUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";

contract MockAA {
    bytes4 internal constant MAGIC_VALUE = bytes4(keccak256("isValidSignature(bytes32,bytes)"));
    address immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function isValidSignature(bytes32 _messageHash, bytes memory _signature) public view returns (bytes4 magicValue) {
        address signatory = ECDSAUpgradeable.recover(_messageHash, _signature);

        if (signatory == owner) {
            return MAGIC_VALUE;
        } else {
            return bytes4(0);
        }
    }
}

contract ZoraCreator1155PreminterTest is Test {
    uint256 internal constant CONTRACT_BASE_ID = 0;
    uint256 internal constant PERMISSION_BIT_MINTER = 2 ** 2;

    ZoraCreator1155PremintExecutorImpl internal preminter;
    Zora1155Factory factoryProxy;
    ZoraCreator1155FactoryImpl factory;

    ICreatorRoyaltiesControl.RoyaltyConfiguration internal defaultRoyaltyConfig;
    uint256 internal mintFeeAmount = 0.000111 ether;

    // setup contract config
    uint256 internal creatorPrivateKey;
    address internal creator;
    address internal zora;
    address internal premintExecutor;
    address internal collector;
    address internal firstMinter;

    MintArguments defaultMintArguments;
    ProtocolRewards rewards;

    function setUp() external {
        (creator, creatorPrivateKey) = makeAddrAndKey("creator");
        zora = makeAddr("zora");
        premintExecutor = makeAddr("premintExecutor");
        collector = makeAddr("collector");
        firstMinter = collector;

        vm.startPrank(zora);
        (rewards, , , factoryProxy, ) = Zora1155FactoryFixtures.setup1155AndFactoryProxy(zora, zora);
        vm.stopPrank();

        factory = ZoraCreator1155FactoryImpl(address(factoryProxy));

        preminter = new ZoraCreator1155PremintExecutorImpl(factory);

        defaultMintArguments = MintArguments({mintRecipient: premintExecutor, mintComment: "blah", mintRewardsRecipients: new address[](0)});
    }

    function makeDefaultContractCreationConfig() internal view returns (ContractWithAdditionalAdminsCreationConfig memory) {
        return
            ContractWithAdditionalAdminsCreationConfig({
                contractAdmin: creator,
                contractName: "blah",
                contractURI: "blah.contract",
                additionalAdmins: new address[](0)
            });
    }

    function getFixedPriceMinter() internal view returns (IMinter1155) {
        return factory.defaultMinters()[0];
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

    function test_premintV2_whenpremintSignerContract_premintSignerContractIsOwner() external {
        // given
        ContractWithAdditionalAdminsCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        MockAA mockAA = new MockAA(creator);
        // contract config admin must be the creator, which in this case is the erc1271 contract.
        contractConfig.contractAdmin = address(mockAA);
        PremintConfigV2 memory premintConfig = makePremintConfigWithCreateReferral(premintExecutor);

        // creator is the one to sign the premint
        bytes memory signature = _signPremint(
            preminter.getContractWithAdditionalAdminsAddress(contractConfig),
            premintConfig,
            creatorPrivateKey,
            block.chainid
        );

        uint256 quantityToMint = 2;
        uint256 mintCost = (mintFeeAmount + premintConfig.tokenConfig.pricePerToken) * quantityToMint;

        // when
        PremintResult memory premintResult = preminter.premint{value: mintCost}(
            contractConfig,
            address(0),
            PremintEncoding.encodePremint(premintConfig),
            signature,
            quantityToMint,
            defaultMintArguments,
            firstMinter,
            address(mockAA)
        );

        // then
        // owner should be the erc1271 contract
        assertEq(IZoraCreator1155(premintResult.contractAddress).owner(), address(mockAA));
    }

    function test_premintV2_whenpremintSignerContract_revertsWhen_nonContractAtpremintSignerContract() external {
        // given
        ContractWithAdditionalAdminsCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        // contract config admin must be the creator, which in this case is the erc1271 contract.
        PremintConfigV2 memory premintConfig = makePremintConfigWithCreateReferral(premintExecutor);

        // creator is the one to sign the premint
        bytes memory signature = _signPremint(
            preminter.getContractWithAdditionalAdminsAddress(contractConfig),
            premintConfig,
            creatorPrivateKey,
            block.chainid
        );

        uint256 quantityToMint = 2;
        uint256 mintCost = (mintFeeAmount + premintConfig.tokenConfig.pricePerToken) * quantityToMint;

        // this should revert - because the smart wallet param is not a contract.
        vm.expectRevert(IZoraCreator1155Errors.premintSignerContractNotAContract.selector);
        preminter.premint{value: mintCost}(
            contractConfig,
            address(0),
            PremintEncoding.encodePremint(premintConfig),
            signature,
            quantityToMint,
            defaultMintArguments,
            firstMinter,
            creator
        );
    }

    function test_premintV2_whenpremintSignerContract_revertsWhen_premintSignerContractRejectsSigner() external {
        // given
        ContractWithAdditionalAdminsCreationConfig memory contractConfig = makeDefaultContractCreationConfig();

        PremintConfigV2 memory premintConfig = makePremintConfigWithCreateReferral(premintExecutor);

        // make a mock erc1271 that be the smart wallet that validates the signature on the creators behalf
        MockAA mockAA = new MockAA(creator);
        contractConfig.contractAdmin = address(mockAA);

        // have another account sign the premint - it should be rejected
        (, uint256 otherPrivateKey) = makeAddrAndKey("other");
        bytes memory signature = _signPremint(preminter.getContractWithAdditionalAdminsAddress(contractConfig), premintConfig, otherPrivateKey, block.chainid);

        uint256 quantityToMint = 2;
        uint256 mintCost = (mintFeeAmount + premintConfig.tokenConfig.pricePerToken) * quantityToMint;

        vm.expectRevert(abi.encodeWithSelector(IZoraCreator1155Errors.InvalidSigner.selector, bytes4(0)));
        preminter.premint{value: mintCost}(
            contractConfig,
            address(0),
            PremintEncoding.encodePremint(premintConfig),
            signature,
            quantityToMint,
            defaultMintArguments,
            firstMinter,
            address(mockAA)
        );
    }

    function test_premintV2_whenpremintSignerContract_revertsWhen_invalidSignature() external {
        // given
        ContractWithAdditionalAdminsCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        MockAA mockAA = new MockAA(creator);
        // contract config admin must be the creator, which in this case is the erc1271 contract.
        contractConfig.contractAdmin = address(mockAA);
        PremintConfigV2 memory premintConfig = makePremintConfigWithCreateReferral(premintExecutor);

        // creator is the one to sign the premint
        uint256 quantityToMint = 2;
        uint256 mintCost = (mintFeeAmount + premintConfig.tokenConfig.pricePerToken) * quantityToMint;

        // make the signature bad
        bytes memory signature = abi.encodePacked("bad");

        vm.expectRevert(IZoraCreator1155Errors.premintSignerContractFailedToRecoverSigner.selector);
        preminter.premint{value: mintCost}(
            contractConfig,
            address(0),
            PremintEncoding.encodePremint(premintConfig),
            signature,
            quantityToMint,
            defaultMintArguments,
            firstMinter,
            address(mockAA)
        );
    }

    function test_premintV2_whenpremintSignerContract_revertsWhen_premintSignerContractNotAContract() external {
        // given
        ContractWithAdditionalAdminsCreationConfig memory contractConfig = makeDefaultContractCreationConfig();
        MockAA mockAA = new MockAA(creator);
        // contract config admin must be the creator, which in this case is the erc1271 contract.
        contractConfig.contractAdmin = address(mockAA);
        PremintConfigV2 memory premintConfig = makePremintConfigWithCreateReferral(premintExecutor);

        // make the signature bad
        vm.expectRevert(IZoraCreator1155Errors.premintSignerContractNotAContract.selector);
        preminter.premint(
            contractConfig,
            address(0),
            PremintEncoding.encodePremint(premintConfig),
            bytes(""),
            1,
            defaultMintArguments,
            firstMinter,
            // here we pass an account thats not a contract - it should revert
            makeAddr("randomAccount")
        );
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
