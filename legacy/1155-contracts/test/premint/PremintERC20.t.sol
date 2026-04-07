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
import {ZoraCreator1155Attribution} from "../../src/delegation/ZoraCreator1155Attribution.sol";
import {TokenCreationConfigV3, PremintConfigV3, MintArguments, ContractWithAdditionalAdminsCreationConfig} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {PremintEncoding} from "@zoralabs/shared-contracts/premint/PremintEncoding.sol";
import {ZoraCreator1155FactoryImpl} from "../../src/factory/ZoraCreator1155FactoryImpl.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155PremintExecutor} from "../../src/proxies/Zora1155PremintExecutor.sol";
import {Zora1155Factory} from "../../src/proxies/Zora1155Factory.sol";
import {Zora1155} from "../../src/proxies/Zora1155.sol";
import {IERC20Minter} from "../../src/interfaces/IERC20Minter.sol";
import {IMinterPremintSetup} from "../../src/interfaces/IMinterPremintSetup.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";

contract PremintERC20Test is Test {
    uint256 internal creatorPK;
    uint256 internal ethReward;
    address internal creator;
    address internal zora;
    address internal collector;
    address internal owner;

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
        owner = makeAddr("owner");
        ethReward = 0.000111 ether;

        mockErc20 = new ERC20PresetMinterPauser("Mock", "MOCK");
        erc20Minter = new ERC20Minter();
        erc20Minter.initialize(zora, owner, 5, ethReward);
        protocolRewards = new ProtocolRewards();

        zora1155Impl = address(new ZoraCreator1155Impl(zora, address(new UpgradeGate()), address(protocolRewards), makeAddr("timedSaleStrategy")));
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
        ContractWithAdditionalAdminsCreationConfig memory contractConfig = ContractWithAdditionalAdminsCreationConfig({
            contractAdmin: creator,
            contractName: "test",
            contractURI: "test.uri",
            additionalAdmins: new address[](0)
        });

        IERC20Minter.PremintSalesConfig memory premintSalesConfig = IERC20Minter.PremintSalesConfig({
            currency: address(mockErc20),
            pricePerToken: 1e18,
            maxTokensPerAddress: 5000,
            duration: 1000,
            fundsRecipient: collector
        });

        TokenCreationConfigV3 memory tokenConfig = TokenCreationConfigV3({
            tokenURI: "test.token.uri",
            maxSupply: 1000,
            royaltyBPS: 0,
            payoutRecipient: collector,
            createReferral: address(0),
            minter: address(erc20Minter),
            mintStart: 0,
            premintSalesConfig: abi.encode(premintSalesConfig)
        });

        PremintConfigV3 memory premintConfig = PremintConfigV3({tokenConfig: tokenConfig, uid: 1, version: 3, deleted: false});

        address contractAddress = premint.getContractWithAdditionalAdminsAddress(contractConfig);
        bytes memory signature = signPremint(premintConfig, contractAddress);

        MintArguments memory mintArguments = MintArguments({mintRecipient: collector, mintComment: "test comment", mintRewardsRecipients: new address[](0)});

        uint256 quantityToMint = 3;
        uint256 totalValue = premintSalesConfig.pricePerToken * quantityToMint;
        mockErc20.mint(collector, totalValue);

        vm.prank(collector);
        mockErc20.approve(address(premint), totalValue);

        uint256 totalEthReward = ethReward * quantityToMint;

        vm.deal(collector, totalEthReward);
        vm.prank(collector);
        // validate that the erc20 minter is called with the correct arguments
        vm.expectCall(
            address(erc20Minter),
            totalEthReward,
            abi.encodeCall(erc20Minter.mint, (collector, quantityToMint, contractAddress, 1, totalValue, address(mockErc20), address(0), "test comment"))
        );
        premint.premint{value: totalEthReward}(
            contractConfig,
            address(0),
            PremintEncoding.encodePremint(premintConfig),
            signature,
            quantityToMint,
            mintArguments,
            collector,
            address(0)
        );

        // validate that the erc20 minter has the proper sales config set
        IERC20Minter.SalesConfig memory salesConfig = erc20Minter.sale(contractAddress, 1);
        assertEq(salesConfig.saleStart, uint64(block.timestamp));
        assertEq(salesConfig.saleEnd, uint64(block.timestamp) + premintSalesConfig.duration);
    }

    function testRevertExecutorMustApproveERC20Transfer() public {
        ContractWithAdditionalAdminsCreationConfig memory contractConfig = ContractWithAdditionalAdminsCreationConfig({
            contractAdmin: creator,
            contractName: "test",
            contractURI: "test.uri",
            additionalAdmins: new address[](0)
        });

        IERC20Minter.PremintSalesConfig memory premintSalesConfig = IERC20Minter.PremintSalesConfig({
            currency: address(mockErc20),
            pricePerToken: 1e18,
            maxTokensPerAddress: 0,
            duration: 0,
            fundsRecipient: collector
        });

        TokenCreationConfigV3 memory tokenConfig = TokenCreationConfigV3({
            tokenURI: "test.token.uri",
            maxSupply: 1000,
            royaltyBPS: 0,
            payoutRecipient: collector,
            createReferral: address(0),
            minter: address(erc20Minter),
            mintStart: 0,
            premintSalesConfig: abi.encode(premintSalesConfig)
        });

        PremintConfigV3 memory premintConfig = PremintConfigV3({tokenConfig: tokenConfig, uid: 1, version: 3, deleted: false});

        address contractAddress = premint.getContractWithAdditionalAdminsAddress(contractConfig);
        bytes memory signature = signPremint(premintConfig, contractAddress);

        MintArguments memory mintArguments = MintArguments({mintRecipient: collector, mintComment: "test comment", mintRewardsRecipients: new address[](0)});

        uint256 quantityToMint = 1;
        uint256 totalValue = premintSalesConfig.pricePerToken * quantityToMint;
        mockErc20.mint(collector, totalValue);

        uint256 totalEthReward = ethReward * quantityToMint;

        vm.deal(collector, totalEthReward);
        vm.prank(collector);
        vm.expectRevert("ERC20: insufficient allowance");
        premint.premint{value: totalEthReward}(
            contractConfig,
            address(0),
            PremintEncoding.encodePremint(premintConfig),
            signature,
            quantityToMint,
            mintArguments,
            collector,
            address(0)
        );
    }

    function signPremint(PremintConfigV3 memory premintConfig, address contractAddress) public view returns (bytes memory) {
        bytes32 structHash = ZoraCreator1155Attribution.hashPremint(premintConfig);
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(structHash, contractAddress, PremintEncoding.HASHED_VERSION_3, block.chainid);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(creatorPK, digest);
        return abi.encodePacked(r, s, v);
    }
}
