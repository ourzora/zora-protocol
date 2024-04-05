// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {ProtocolRewards} from "@zoralabs/protocol-rewards/src/ProtocolRewards.sol";
import {UpgradeGate} from "../../src/upgrades/UpgradeGate.sol";
import {ERC20Minter} from "../../src/minters/erc20/ERC20Minter.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155PremintExecutor, ZoraCreator1155PremintExecutorImpl} from "../../src/delegation/ZoraCreator1155PremintExecutorImpl.sol";
import {ZoraCreator1155PremintExecutorImplLib} from "../../src/delegation/ZoraCreator1155PremintExecutorImplLib.sol";
import {ZoraCreator1155Attribution, ContractCreationConfig} from "../../src/delegation/ZoraCreator1155Attribution.sol";
import {Erc20TokenCreationConfigV1, Erc20PremintConfigV1, MintArguments} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {PremintEncoding} from "@zoralabs/shared-contracts/premint/PremintEncoding.sol";
import {ZoraCreator1155FactoryImpl} from "../../src/factory/ZoraCreator1155FactoryImpl.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155PremintExecutor} from "../../src/proxies/Zora1155PremintExecutor.sol";
import {Zora1155Factory} from "../../src/proxies/Zora1155Factory.sol";
import {Zora1155} from "../../src/proxies/Zora1155.sol";

contract PremintERC20Test is Test {
    uint256 internal creatorPK;
    address internal creator;
    address internal zora;
    address internal collector;

    ProtocolRewards internal protocolRewards;
    ERC20Minter internal erc20Minter;
    ERC20PresetMinterPauser internal mockErc20;

    address internal zora1155Impl;
    address internal factoryImpl;
    address internal premintImpl;

    ZoraCreator1155FactoryImpl internal factory;
    ZoraCreator1155PremintExecutorImpl internal premint;

    function setUp() public {
        (creator, creatorPK) = makeAddrAndKey("creator");
        collector = makeAddr("collector");
        zora = makeAddr("zora");

        mockErc20 = new ERC20PresetMinterPauser("Mock", "MOCK");
        erc20Minter = new ERC20Minter();
        erc20Minter.initialize(zora);
        protocolRewards = new ProtocolRewards();

        zora1155Impl = address(new ZoraCreator1155Impl(zora, address(new UpgradeGate()), address(protocolRewards), address(0)));
        factoryImpl = address(
            new ZoraCreator1155FactoryImpl(IZoraCreator1155(zora1155Impl), IMinter1155(address(0)), IMinter1155(address(0)), IMinter1155(address(0)))
        );
        factory = ZoraCreator1155FactoryImpl(address(new Zora1155Factory(factoryImpl, abi.encodeWithSignature("initialize(address)", zora))));
        premintImpl = address(new ZoraCreator1155PremintExecutorImpl(factory));
        premint = ZoraCreator1155PremintExecutorImpl(address(new Zora1155PremintExecutor(premintImpl, abi.encodeWithSignature("initialize(address)", zora))));

        vm.label(address(factory), "FACTORY_CONTRACT");
        vm.label(address(premint), "PREMINT_CONTRACT");
    }

    function testPremintERC20() public {
        ContractCreationConfig memory contractConfig = ContractCreationConfig({contractAdmin: creator, contractName: "test", contractURI: "test.uri"});

        Erc20TokenCreationConfigV1 memory tokenConfig = Erc20TokenCreationConfigV1({
            tokenURI: "test.token.uri",
            maxSupply: 1000,
            royaltyBPS: 0,
            payoutRecipient: collector,
            createReferral: address(0),
            erc20Minter: address(erc20Minter),
            mintStart: 0,
            mintDuration: 0,
            maxTokensPerAddress: 0,
            currency: address(mockErc20),
            pricePerToken: 1e18
        });

        Erc20PremintConfigV1 memory premintConfig = Erc20PremintConfigV1({tokenConfig: tokenConfig, uid: 1, version: 3, deleted: false});

        address contractAddress = premint.getContractAddress(contractConfig);
        bytes32 structHash = ZoraCreator1155Attribution.hashPremint(premintConfig);
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(structHash, contractAddress, PremintEncoding.HASHED_ERC20_VERSION_1, block.chainid);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(creatorPK, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        MintArguments memory mintArguments = MintArguments({mintRecipient: collector, mintComment: "test comment", mintRewardsRecipients: new address[](0)});

        uint256 quantityToMint = 1;
        uint256 totalValue = tokenConfig.pricePerToken * quantityToMint;
        mockErc20.mint(collector, totalValue);

        vm.prank(collector);
        mockErc20.approve(address(premint), totalValue);

        vm.prank(collector);
        premint.premintErc20V1(contractConfig, premintConfig, signature, quantityToMint, mintArguments, collector, address(0));
    }

    function testRevertExecutorMustApproveERC20Transfer() public {
        ContractCreationConfig memory contractConfig = ContractCreationConfig({contractAdmin: creator, contractName: "test", contractURI: "test.uri"});

        Erc20TokenCreationConfigV1 memory tokenConfig = Erc20TokenCreationConfigV1({
            tokenURI: "test.token.uri",
            maxSupply: 1000,
            royaltyBPS: 0,
            payoutRecipient: collector,
            createReferral: address(0),
            erc20Minter: address(erc20Minter),
            mintStart: 0,
            mintDuration: 0,
            maxTokensPerAddress: 0,
            currency: address(mockErc20),
            pricePerToken: 1e18
        });

        Erc20PremintConfigV1 memory premintConfig = Erc20PremintConfigV1({tokenConfig: tokenConfig, uid: 1, version: 3, deleted: false});

        address contractAddress = premint.getContractAddress(contractConfig);
        bytes32 structHash = ZoraCreator1155Attribution.hashPremint(premintConfig);
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(structHash, contractAddress, PremintEncoding.HASHED_ERC20_VERSION_1, block.chainid);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(creatorPK, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        MintArguments memory mintArguments = MintArguments({mintRecipient: collector, mintComment: "test comment", mintRewardsRecipients: new address[](0)});

        uint256 quantityToMint = 1;
        uint256 totalValue = tokenConfig.pricePerToken * quantityToMint;
        mockErc20.mint(collector, totalValue);

        vm.prank(collector);
        vm.expectRevert("ERC20: insufficient allowance");
        premint.premintErc20V1(contractConfig, premintConfig, signature, quantityToMint, mintArguments, collector, address(0));
    }
}
