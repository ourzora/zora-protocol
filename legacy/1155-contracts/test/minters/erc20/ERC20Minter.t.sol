// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ProtocolRewards} from "@zoralabs/protocol-rewards/src/ProtocolRewards.sol";
import {ZoraCreator1155Impl} from "../../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155} from "../../../src/proxies/Zora1155.sol";
import {IMinter1155} from "../../../src/interfaces/IMinter1155.sol";
import {ICreatorRoyaltiesControl} from "../../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {ILimitedMintPerAddressErrors} from "../../../src/interfaces/ILimitedMintPerAddress.sol";
import {ERC20PresetMinterPauser} from "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import {ERC20Minter} from "../../../src/minters/erc20/ERC20Minter.sol";
import {IERC20Minter} from "../../../src/interfaces/IERC20Minter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IZoraCreator1155Errors} from "../../../src/interfaces/IZoraCreator1155Errors.sol";

contract ERC20MinterTest is Test {
    ZoraCreator1155Impl internal target;
    ERC20PresetMinterPauser currency;
    address payable internal admin = payable(address(0x999));
    address internal zora;
    address internal tokenRecipient;
    address internal fundsRecipient;
    address internal createReferral;
    address internal mintReferral;
    address internal owner;
    ERC20Minter internal minter;
    IERC20Minter.ERC20MinterConfig internal minterConfig;

    uint256 internal constant TOTAL_REWARD_PCT = 5;
    uint256 immutable BPS_TO_PERCENT = 100;
    uint256 internal constant CREATE_REFERRAL_PAID_MINT_REWARD_PCT = 28_571400;
    uint256 internal constant MINT_REFERRAL_PAID_MINT_REWARD_PCT = 28_571400;
    uint256 internal constant ZORA_PAID_MINT_REWARD_PCT = 28_571400;
    uint256 internal constant FIRST_MINTER_REWARD_PCT = 14_228500;
    uint256 immutable BPS_TO_PERCENT_8_DECIMAL_PERCISION = 100_000_000;
    uint256 internal constant ethReward = 0.000111 ether;

    event ERC20RewardsDeposit(
        address indexed createReferral,
        address indexed mintReferral,
        address indexed firstMinter,
        address zora,
        address collection,
        address currency,
        uint256 tokenId,
        uint256 createReferralReward,
        uint256 mintReferralReward,
        uint256 firstMinterReward,
        uint256 zoraReward
    );

    event ERC20MinterConfigSet(IERC20Minter.ERC20MinterConfig config);

    event OwnerSet(address indexed prevOwner, address indexed owner);

    event MintComment(address indexed sender, address indexed tokenContract, uint256 indexed tokenId, uint256 quantity, string comment);

    function setUp() external {
        zora = makeAddr("zora");
        tokenRecipient = makeAddr("tokenRecipient");
        fundsRecipient = makeAddr("fundsRecipient");
        createReferral = makeAddr("createReferral");
        mintReferral = makeAddr("mintReferral");
        owner = makeAddr("owner");

        bytes[] memory emptyData = new bytes[](0);
        ProtocolRewards protocolRewards = new ProtocolRewards();
        ZoraCreator1155Impl targetImpl = new ZoraCreator1155Impl(zora, address(0x1234), address(protocolRewards), address(0));
        Zora1155 proxy = new Zora1155(address(targetImpl));
        target = ZoraCreator1155Impl(payable(address(proxy)));
        target.initialize("test", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), admin, emptyData);
        minter = new ERC20Minter();
        minter.initialize(zora, owner, 5, ethReward);
        vm.prank(admin);
        currency = new ERC20PresetMinterPauser("Test currency", "TEST");
        minterConfig = minter.getERC20MinterConfig();
    }

    function setUpTargetSale(
        uint256 price,
        address tokenFundsRecipient,
        address tokenCurrency,
        uint256 quantity,
        ERC20Minter minterContract
    ) internal returns (uint256) {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewTokenWithCreateReferral("https://zora.co/testing/token.json", quantity, createReferral);
        target.addPermission(newTokenId, address(minterContract), target.PERMISSION_BIT_MINTER());
        target.callSale(
            newTokenId,
            minterContract,
            abi.encodeWithSelector(
                ERC20Minter.setSale.selector,
                newTokenId,
                IERC20Minter.SalesConfig({
                    pricePerToken: price,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: tokenFundsRecipient,
                    currency: tokenCurrency
                })
            )
        );
        vm.stopPrank();

        return newTokenId;
    }

    function test_ERC20MinterInitializeEventIsEmitted() external {
        vm.expectEmit(true, true, true, true);
        IERC20Minter.ERC20MinterConfig memory newConfig = IERC20Minter.ERC20MinterConfig({
            zoraRewardRecipientAddress: zora,
            rewardRecipientPercentage: 5,
            ethReward: ethReward
        });
        emit ERC20MinterConfigSet(newConfig);

        minter = new ERC20Minter();
        minter.initialize(zora, owner, 5, ethReward);
    }

    function test_ERC20MinterZoraAddrCannotInitializeWithAddressZero() external {
        minter = new ERC20Minter();

        vm.expectRevert(abi.encodeWithSignature("AddressZero()"));
        minter.initialize(address(0), owner, 5, ethReward);
    }

    function test_ERC20MinterOwnerAddrCannotInitializeWithAddressZero() external {
        minter = new ERC20Minter();

        vm.expectRevert(abi.encodeWithSignature("OWNER_CANNOT_BE_ZERO_ADDRESS()"));
        minter.initialize(zora, address(0), 5, ethReward);
    }

    function test_ERC20MinterRewardPercentageCannotBeGreaterThan100() external {
        minter = new ERC20Minter();

        vm.expectRevert(abi.encodeWithSignature("InvalidValue()"));
        minter.initialize(zora, owner, 101, ethReward);
    }

    function test_ERC20MinterContractName() external {
        assertEq(minter.contractName(), "ERC20 Minter");
    }

    function test_ERC20MinterContractVersion() external {
        assertEq(minter.contractVersion(), "2.0.0");
    }

    function test_ERC20MinterAlreadyInitalized() external {
        minter = new ERC20Minter();
        minter.initialize(zora, owner, 5, ethReward);

        vm.expectRevert(abi.encodeWithSignature("INITIALIZABLE_CONTRACT_ALREADY_INITIALIZED()"));
        minter.initialize(zora, owner, 5, ethReward);
    }

    function test_ERC20MinterSaleConfigPriceTooLow() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(minter), target.PERMISSION_BIT_MINTER());

        bytes memory minterError = abi.encodeWithSignature("PricePerTokenTooLow()");
        vm.expectRevert(abi.encodeWithSignature("CallFailed(bytes)", minterError));
        target.callSale(
            newTokenId,
            minter,
            abi.encodeWithSelector(
                ERC20Minter.setSale.selector,
                newTokenId,
                IERC20Minter.SalesConfig({
                    pricePerToken: 1,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0x123),
                    currency: address(currency)
                })
            )
        );
        vm.stopPrank();
    }

    function test_ERC20MinterRevertIfFundsRecipientAddressZero() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewTokenWithCreateReferral("https://zora.co/testing/token.json", 1, createReferral);
        target.addPermission(newTokenId, address(minter), target.PERMISSION_BIT_MINTER());

        bytes memory minterError = abi.encodeWithSignature("AddressZero()");
        vm.expectRevert(abi.encodeWithSignature("CallFailed(bytes)", minterError));
        target.callSale(
            newTokenId,
            minter,
            abi.encodeWithSelector(
                ERC20Minter.setSale.selector,
                newTokenId,
                IERC20Minter.SalesConfig({
                    pricePerToken: 10_000,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0),
                    currency: address(currency)
                })
            )
        );
        vm.stopPrank();
    }

    function test_ERC20MinterRevertIfCurrencyZero() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewTokenWithCreateReferral("https://zora.co/testing/token.json", 1, createReferral);
        target.addPermission(newTokenId, address(minter), target.PERMISSION_BIT_MINTER());

        bytes memory minterError = abi.encodeWithSignature("AddressZero()");
        vm.expectRevert(abi.encodeWithSignature("CallFailed(bytes)", minterError));
        target.callSale(
            newTokenId,
            minter,
            abi.encodeWithSelector(
                ERC20Minter.setSale.selector,
                newTokenId,
                IERC20Minter.SalesConfig({
                    pricePerToken: 10_000,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: fundsRecipient,
                    currency: address(0)
                })
            )
        );
        vm.stopPrank();
    }

    function test_ERC20MinterRevertIfCurrencyDoesNotMatchSalesConfigCurrency() external {
        setUpTargetSale(10_000, fundsRecipient, address(currency), 1, minter);

        vm.deal(tokenRecipient, ethReward);

        vm.expectRevert(abi.encodeWithSignature("InvalidCurrency()"));
        minter.mint{value: ethReward}(tokenRecipient, 1, address(target), 1, 1, makeAddr("0x123"), address(0), "");
    }

    function test_ERC20MinterRequestMintInvalid() external {
        vm.expectRevert(abi.encodeWithSignature("RequestMintInvalidUseMint()"));
        minter.requestMint(address(0), 1, 1, 1, "");
    }

    function test_ERC20MinterComputePaidMintRewards() external {
        uint256 totalValue = 500000000000000000; // 0.5 when converted from wei
        ERC20Minter.RewardsSettings memory rewardsSettings = minter.computePaidMintRewards(totalValue);

        assertEq(rewardsSettings.createReferralReward, 142857000000000000);
        assertEq(rewardsSettings.mintReferralReward, 142857000000000000);
        assertEq(rewardsSettings.firstMinterReward, 71142500000000000);
        assertEq(rewardsSettings.zoraReward, 143143500000000000);
        assertEq(
            rewardsSettings.createReferralReward + rewardsSettings.mintReferralReward + rewardsSettings.zoraReward + rewardsSettings.firstMinterReward,
            totalValue
        );
    }

    function test_ERC20MinterSaleFlow() external {
        uint96 pricePerToken = 10_000;
        uint256 quantity = 2;
        uint256 newTokenId = setUpTargetSale(pricePerToken, fundsRecipient, address(currency), quantity, minter);

        vm.deal(tokenRecipient, 1 ether);
        vm.prank(admin);
        uint256 totalValue = pricePerToken * quantity;
        currency.mint(address(tokenRecipient), totalValue);

        vm.prank(tokenRecipient);
        currency.approve(address(minter), totalValue);

        vm.deal(tokenRecipient, ethReward * quantity);

        vm.startPrank(tokenRecipient);
        minter.mint{value: ethReward * quantity}(
            tokenRecipient,
            quantity,
            address(target),
            newTokenId,
            pricePerToken * quantity,
            address(currency),
            mintReferral,
            ""
        );
        vm.stopPrank();

        assertEq(target.balanceOf(tokenRecipient, newTokenId), quantity);
        assertEq(currency.balanceOf(fundsRecipient), 19000);
        assertEq(currency.balanceOf(address(zora)), 288);
        assertEq(currency.balanceOf(mintReferral), 285);
        assertEq(currency.balanceOf(admin), 142);
        assertEq(currency.balanceOf(createReferral), 285);
        assertEq(
            currency.balanceOf(address(zora)) +
                currency.balanceOf(fundsRecipient) +
                currency.balanceOf(mintReferral) +
                currency.balanceOf(admin) +
                currency.balanceOf(createReferral),
            totalValue
        );
        assertEq(address(zora).balance, ethReward * quantity);
    }

    function test_ERC20MinterSaleWithRewardsAddresses() external {
        uint96 pricePerToken = 100000000000000000; // 0.1 when converted from wei
        uint256 quantity = 5;
        uint256 newTokenId = setUpTargetSale(pricePerToken, fundsRecipient, address(currency), quantity, minter);

        vm.deal(tokenRecipient, ethReward * quantity);
        vm.prank(admin);
        uint256 totalValue = pricePerToken * quantity;
        currency.mint(address(tokenRecipient), totalValue);

        vm.prank(tokenRecipient);
        currency.approve(address(minter), totalValue);

        vm.startPrank(tokenRecipient);
        minter.mint{value: ethReward * quantity}(
            tokenRecipient,
            quantity,
            address(target),
            newTokenId,
            pricePerToken * quantity,
            address(currency),
            mintReferral,
            ""
        );
        vm.stopPrank();

        assertEq(target.balanceOf(tokenRecipient, newTokenId), quantity);
        assertEq(currency.balanceOf(fundsRecipient), 475000000000000000);
        assertEq(currency.balanceOf(address(zora)), 7157175000000000);
        assertEq(currency.balanceOf(createReferral), 7142850000000000);
        assertEq(currency.balanceOf(mintReferral), 7142850000000000);
        assertEq(
            currency.balanceOf(address(zora)) +
                currency.balanceOf(fundsRecipient) +
                currency.balanceOf(createReferral) +
                currency.balanceOf(mintReferral) +
                currency.balanceOf(admin),
            totalValue
        );
        assertEq(address(zora).balance, ethReward * quantity);
    }

    function test_ERC20MinterSaleFuzz(uint96 pricePerToken, uint256 quantity, uint8 rewardPct, uint256 zoraEthReward) external {
        vm.assume(quantity > 0 && quantity < 1_000_000_000);
        vm.assume(pricePerToken > 10_000 && pricePerToken < type(uint96).max);
        vm.assume(rewardPct > 0 && rewardPct < 100);
        vm.assume(zoraEthReward > 0 ether && zoraEthReward < 1 ether);

        ERC20Minter newMinter = new ERC20Minter();
        newMinter.initialize(address(zora), owner, rewardPct, zoraEthReward);

        uint256 tokenId = setUpTargetSale(pricePerToken, fundsRecipient, address(currency), quantity, newMinter);

        vm.prank(admin);
        uint256 totalValue = pricePerToken * quantity;
        currency.mint(address(tokenRecipient), totalValue);

        vm.prank(tokenRecipient);
        currency.approve(address(newMinter), totalValue);

        uint256 reward = (totalValue * rewardPct) / BPS_TO_PERCENT;
        uint256 createReferralReward = (reward * CREATE_REFERRAL_PAID_MINT_REWARD_PCT) / BPS_TO_PERCENT_8_DECIMAL_PERCISION;
        uint256 mintReferralReward = (reward * MINT_REFERRAL_PAID_MINT_REWARD_PCT) / BPS_TO_PERCENT_8_DECIMAL_PERCISION;
        uint256 firstMinterReward = (reward * FIRST_MINTER_REWARD_PCT) / BPS_TO_PERCENT_8_DECIMAL_PERCISION;
        uint256 zoraReward = reward - (createReferralReward + mintReferralReward + firstMinterReward);

        vm.startPrank(tokenRecipient);
        vm.expectEmit(true, true, true, true);
        emit ERC20RewardsDeposit(
            createReferral,
            mintReferral,
            address(admin),
            zora,
            address(target),
            address(currency),
            tokenId,
            createReferralReward,
            mintReferralReward,
            firstMinterReward,
            zoraReward
        );
        vm.deal(tokenRecipient, zoraEthReward * quantity);

        uint256 amount = pricePerToken * quantity;
        newMinter.mint{value: zoraEthReward * quantity}(tokenRecipient, quantity, address(target), tokenId, amount, address(currency), mintReferral, "");
        vm.stopPrank();

        assertEq(target.balanceOf(tokenRecipient, tokenId), quantity);
        assertEq(currency.balanceOf(address(zora)), zoraReward);
        assertEq(currency.balanceOf(createReferral), createReferralReward);
        assertEq(currency.balanceOf(mintReferral), mintReferralReward);
        assertEq(currency.balanceOf(admin), firstMinterReward);
        assertEq(currency.balanceOf(address(zora)) + currency.balanceOf(mintReferral) + currency.balanceOf(admin) + currency.balanceOf(createReferral), reward);
        assertEq(
            currency.balanceOf(address(zora)) +
                currency.balanceOf(fundsRecipient) +
                currency.balanceOf(createReferral) +
                currency.balanceOf(mintReferral) +
                currency.balanceOf(admin),
            totalValue
        );
        assertEq(address(zora).balance, zoraEthReward * quantity);
    }

    function test_ERC20MinterCreateReferral() public {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewTokenWithCreateReferral("https://zora.co/testing/token.json", 1, createReferral);
        target.addPermission(newTokenId, address(minter), target.PERMISSION_BIT_MINTER());
        vm.stopPrank();

        address targetCreateReferral = minter.getCreateReferral(address(target), newTokenId);
        assertEq(targetCreateReferral, createReferral);

        address fallbackCreateReferral = minter.getCreateReferral(address(this), 1);
        assertEq(fallbackCreateReferral, minterConfig.zoraRewardRecipientAddress);
    }

    function test_ERC20MinterFirstMinterFallback() public {
        uint256 pricePerToken = 1e18;
        uint256 quantity = 11;
        uint256 totalValue = pricePerToken * quantity;

        uint256 tokenId = setUpTargetSale(pricePerToken, fundsRecipient, address(currency), quantity, minter);
        address collector = makeAddr("collector");

        vm.prank(admin);
        currency.mint(collector, totalValue);

        vm.deal(collector, ethReward * quantity);

        vm.startPrank(collector);
        currency.approve(address(minter), totalValue);
        minter.mint{value: ethReward * quantity}(collector, quantity, address(target), tokenId, totalValue, address(currency), address(0), "");
        vm.stopPrank();

        address firstMinter = minter.getFirstMinter(address(target), tokenId);
        assertEq(firstMinter, admin);

        address fallbackFirstMinter = minter.getFirstMinter(address(this), 1);
        assertEq(fallbackFirstMinter, minterConfig.zoraRewardRecipientAddress);
    }

    function test_ERC20MinterSetZoraRewardsRecipient() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        IERC20Minter.ERC20MinterConfig memory newConfig = IERC20Minter.ERC20MinterConfig({
            zoraRewardRecipientAddress: address(this),
            rewardRecipientPercentage: 5,
            ethReward: ethReward
        });
        emit ERC20MinterConfigSet(newConfig);
        minter.setERC20MinterConfig(newConfig);

        minterConfig = minter.getERC20MinterConfig();
        assertEq(minterConfig.zoraRewardRecipientAddress, address(this));
    }

    function test_ERC20MinterOnlyRecipientAddressCanSet() public {
        vm.expectRevert(abi.encodeWithSignature("ONLY_OWNER()"));
        IERC20Minter.ERC20MinterConfig memory newConfig = IERC20Minter.ERC20MinterConfig({
            zoraRewardRecipientAddress: address(this),
            rewardRecipientPercentage: 5,
            ethReward: ethReward
        });
        minter.setERC20MinterConfig(newConfig);
    }

    function test_ERC20MinterCannotSetRecipientToZero() public {
        vm.expectRevert(abi.encodeWithSignature("AddressZero()"));
        vm.prank(owner);
        IERC20Minter.ERC20MinterConfig memory newConfig = IERC20Minter.ERC20MinterConfig({
            zoraRewardRecipientAddress: address(0),
            rewardRecipientPercentage: 5,
            ethReward: ethReward
        });
        minter.setERC20MinterConfig(newConfig);
    }

    function test_ERC20SetRewardRecipientPercentage(uint256 percentageFuzz) public {
        vm.assume(percentageFuzz > 0 && percentageFuzz < 100);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidValue()"));
        IERC20Minter.ERC20MinterConfig memory newConfig = IERC20Minter.ERC20MinterConfig({
            zoraRewardRecipientAddress: zora,
            rewardRecipientPercentage: 101,
            ethReward: ethReward
        });
        minter.setERC20MinterConfig(newConfig);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        newConfig = IERC20Minter.ERC20MinterConfig({zoraRewardRecipientAddress: zora, rewardRecipientPercentage: percentageFuzz, ethReward: ethReward});
        emit ERC20MinterConfigSet(newConfig);
        minter.setERC20MinterConfig(newConfig);
    }

    function test_ERC20MinterSetEthReward(uint256 ethRewardFuzz) public {
        vm.assume(ethRewardFuzz >= 0 ether && ethRewardFuzz < 10 ether);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        IERC20Minter.ERC20MinterConfig memory newConfig = IERC20Minter.ERC20MinterConfig({
            zoraRewardRecipientAddress: zora,
            rewardRecipientPercentage: minterConfig.rewardRecipientPercentage,
            ethReward: ethRewardFuzz
        });
        emit ERC20MinterConfigSet(newConfig);
        minter.setERC20MinterConfig(newConfig);
    }

    function test_ERC20MinterSetOwner() public {
        vm.prank(zora);
        vm.expectRevert(abi.encodeWithSignature("ONLY_OWNER()"));
        IERC20Minter.ERC20MinterConfig memory newConfig = IERC20Minter.ERC20MinterConfig({
            zoraRewardRecipientAddress: zora,
            rewardRecipientPercentage: minterConfig.rewardRecipientPercentage,
            ethReward: ethReward
        });
        minter.setERC20MinterConfig(newConfig);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        newConfig = IERC20Minter.ERC20MinterConfig({
            zoraRewardRecipientAddress: zora,
            rewardRecipientPercentage: minterConfig.rewardRecipientPercentage,
            ethReward: ethReward
        });
        emit ERC20MinterConfigSet(newConfig);
        minter.setERC20MinterConfig(newConfig);
    }

    function test_ERC20MinterEthRewardTooLow(uint256 ethRewardLow) public {
        vm.assume(ethRewardLow >= 0 ether && ethRewardLow < 0.000111 ether);

        uint96 pricePerToken = 10_000;
        uint256 quantity = 2;
        uint256 newTokenId = setUpTargetSale(pricePerToken, fundsRecipient, address(currency), quantity, minter);

        vm.deal(tokenRecipient, 1 ether);
        vm.prank(admin);
        uint256 totalValue = pricePerToken * quantity;
        currency.mint(address(tokenRecipient), totalValue);

        vm.prank(tokenRecipient);
        currency.approve(address(minter), totalValue);

        vm.deal(tokenRecipient, ethRewardLow);

        vm.startPrank(tokenRecipient);
        vm.expectRevert(abi.encodeWithSelector(IERC20Minter.InvalidETHValue.selector, 0.000111 ether * quantity, ethRewardLow));
        minter.mint{value: ethRewardLow}(tokenRecipient, quantity, address(target), newTokenId, pricePerToken * quantity, address(currency), mintReferral, "");
        vm.stopPrank();
    }

    function test_ERC20MinterSetPremintSale() public {
        IERC20Minter.PremintSalesConfig memory newConfig = IERC20Minter.PremintSalesConfig({
            duration: 3000,
            maxTokensPerAddress: 200,
            pricePerToken: 50000,
            fundsRecipient: makeAddr("fundsRecipient"),
            currency: makeAddr("currency")
        });
        address erc1155Contract = makeAddr("contract");
        uint256 tokenId = 10;

        vm.prank(erc1155Contract);
        minter.setPremintSale(10, abi.encode(newConfig));

        IERC20Minter.SalesConfig memory salesConfig = minter.sale(erc1155Contract, tokenId);

        assertEq(salesConfig.pricePerToken, newConfig.pricePerToken);
        assertEq(salesConfig.saleStart, block.timestamp);
        assertEq(salesConfig.saleEnd, block.timestamp + newConfig.duration);
        assertEq(salesConfig.maxTokensPerAddress, newConfig.maxTokensPerAddress);
        assertEq(salesConfig.fundsRecipient, newConfig.fundsRecipient);
        assertEq(salesConfig.currency, newConfig.currency);
    }
}
