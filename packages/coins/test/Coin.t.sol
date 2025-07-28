// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./utils/BaseTest.sol";
import {ISwapRouter} from "../src/interfaces/ISwapRouter.sol";
import {CoinConfigurationVersions} from "../src/libs/CoinConfigurationVersions.sol";
import {CoinConstants} from "../src/libs/CoinConstants.sol";
import {IZoraFactory} from "../src/interfaces/IZoraFactory.sol";
import {IHasRewardsRecipients} from "../src/interfaces/IHasRewardsRecipients.sol";
import {PoolConfiguration} from "../src/interfaces/ICoin.sol";
import {IERC165, IERC7572, ICoin, ICoinComments, IERC20} from "../src/BaseCoin.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {BaseCoin} from "../src/BaseCoin.sol";

contract CoinTest is BaseTest {
    using stdJson for string;

    function setUp() public override {
        super.setUp();
    }

    function test_contract_ierc165_support() public {
        _deployV4Coin();
        assertEq(coinV4.supportsInterface(type(IZoraFactory).interfaceId), false);
        assertEq(coinV4.supportsInterface(bytes4(0x00000000)), false);
        assertEq(coinV4.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(coinV4.supportsInterface(type(IERC7572).interfaceId), true);
        assertEq(coinV4.supportsInterface(type(ICoin).interfaceId), true);
        assertEq(coinV4.supportsInterface(type(ICoinComments).interfaceId), true);
        assertEq(coinV4.supportsInterface(type(IERC7572).interfaceId), true);
    }

    function test_contract_version() public {
        _deployV4Coin();
        string memory package = vm.readFile("./package.json");
        assertEq(package.readString(".version"), coinV4.contractVersion());
    }

    function test_supply_constants() public {
        assertEq(CoinConstants.MAX_TOTAL_SUPPLY, CoinConstants.POOL_LAUNCH_SUPPLY + CoinConstants.CREATOR_LAUNCH_REWARD);

        assertEq(CoinConstants.MAX_TOTAL_SUPPLY, 1_000_000_000e18);
        assertEq(CoinConstants.POOL_LAUNCH_SUPPLY, 990_000_000e18);
        assertEq(CoinConstants.CREATOR_LAUNCH_REWARD, 10_000_000e18);

        _deployV4Coin();
        assertEq(coinV4.totalSupply(), CoinConstants.MAX_TOTAL_SUPPLY);
        assertEq(coinV4.balanceOf(coinV4.payoutRecipient()), CoinConstants.CREATOR_LAUNCH_REWARD);
        assertApproxEqAbs(coinV4.balanceOf(address(coinV4.poolManager())), CoinConstants.POOL_LAUNCH_SUPPLY, 1e18);
    }

    function test_initialize_validation() public {
        address[] memory owners = new address[](1);
        owners[0] = users.creator;

        bytes memory poolConfig_ = _generatePoolConfig(address(weth));

        vm.expectRevert(abi.encodeWithSelector(ICoin.AddressZero.selector));
        (address coinAddress, ) = factory.deploy(address(0), owners, "https://init.com", "Init Token", "INIT", poolConfig_, users.platformReferrer, 0);
        coinV4 = ContentCoin(payable(coinAddress));

        (coinAddress, ) = factory.deploy(users.creator, owners, "https://init.com", "Init Token", "INIT", poolConfig_, users.platformReferrer, 0);
        coinV4 = ContentCoin(payable(coinAddress));

        assertEq(coinV4.payoutRecipient(), users.creator, "creator");
        assertEq(coinV4.platformReferrer(), users.platformReferrer, "platformReferrer");
        assertEq(coinV4.tokenURI(), "https://init.com");
        assertEq(coinV4.name(), "Init Token");
        assertEq(coinV4.symbol(), "INIT");
    }

    function test_invalid_pool_config_version() public {
        bytes memory poolConfig = abi.encode(0, address(weth));

        vm.expectRevert(abi.encodeWithSignature("InvalidPoolVersion()"));
        factory.deploy(users.creator, _getDefaultOwners(), "https://test.com", "Testcoin", "TEST", poolConfig, users.platformReferrer, 0);
    }

    function test_legacy_deploy_deploys_with_default_config() public {
        address[] memory owners = new address[](1);
        owners[0] = users.creator;

        (address coinAddress, ) = ZoraFactoryImpl(address(factory)).deploy(
            users.creator,
            owners,
            "https://init.com",
            "Init Token",
            "INIT",
            users.platformReferrer,
            address(weth),
            0,
            0
        );

        ContentCoin coin = ContentCoin(payable(coinAddress));

        PoolConfiguration memory poolConfig = coin.getPoolConfiguration();

        assertEq(poolConfig.version, CoinConfigurationVersions.DOPPLER_MULTICURVE_UNI_V4_POOL_VERSION);
    }

    function test_erc165_interface_support() public {
        _deployV4Coin();
        assertEq(coinV4.supportsInterface(type(IERC165).interfaceId), true);
        assertEq(coinV4.supportsInterface(type(IHasRewardsRecipients).interfaceId), true);
        assertEq(coinV4.supportsInterface(type(IERC7572).interfaceId), true);
    }

    function test_burn() public {
        _deployV4Coin();
        vm.deal(users.buyer, 1 ether);
        vm.prank(users.buyer);
        _swapSomeCurrencyForCoin(coinV4, address(weth), 1 ether, users.coinRecipient);

        uint256 beforeBalance = coinV4.balanceOf(users.coinRecipient);
        uint256 beforeTotalSupply = coinV4.totalSupply();

        uint256 burnAmount = beforeBalance / 2;

        vm.prank(users.coinRecipient);
        coinV4.burn(burnAmount);

        uint256 afterBalance = coinV4.balanceOf(users.coinRecipient);
        uint256 afterTotalSupply = coinV4.totalSupply();

        assertEq(beforeBalance - afterBalance, burnAmount, "coinRecipient coin balance");
        assertEq(beforeTotalSupply - afterTotalSupply, burnAmount, "coin total supply");
    }

    function test_contract_uri() public {
        _deployV4Coin();
        assertEq(coinV4.contractURI(), "https://test.com");
    }

    function test_set_contract_uri() public {
        _deployV4Coin();
        string memory newURI = "https://new.com";

        vm.prank(users.creator);
        coinV4.setContractURI(newURI);
        assertEq(coinV4.contractURI(), newURI);
    }

    function test_set_contract_uri_reverts_if_not_owner() public {
        _deployV4Coin();
        string memory newURI = "https://new.com";

        vm.expectRevert(abi.encodeWithSelector(MultiOwnable.OnlyOwner.selector));
        coinV4.setContractURI(newURI);
    }

    function test_set_payout_recipient() public {
        _deployV4Coin();
        address newPayoutRecipient = makeAddr("NewPayoutRecipient");

        vm.prank(users.creator);
        coinV4.setPayoutRecipient(newPayoutRecipient);
        assertEq(coinV4.payoutRecipient(), newPayoutRecipient);
    }

    function test_revert_set_payout_recipient_address_zero() public {
        _deployV4Coin();
        address newPayoutRecipient = address(0);

        vm.expectRevert(abi.encodeWithSelector(ICoin.AddressZero.selector));
        vm.prank(users.creator);
        coinV4.setPayoutRecipient(newPayoutRecipient);
    }

    function test_revert_set_payout_recipient_only_owner() public {
        _deployV4Coin();
        address newPayoutRecipient = makeAddr("NewPayoutRecipient");

        vm.expectRevert(abi.encodeWithSelector(MultiOwnable.OnlyOwner.selector));
        coinV4.setPayoutRecipient(newPayoutRecipient);
    }

    function test_update_metadata() public {
        _deployV4Coin();
        string memory newName = "NewName";
        string memory newSymbol = "NEW";

        vm.prank(users.creator);
        vm.expectEmit(true, true, true, true);
        emit ICoin.NameAndSymbolUpdated(users.creator, newName, newSymbol);
        coinV4.setNameAndSymbol(newName, newSymbol);
        assertEq(coinV4.name(), newName);
        assertEq(coinV4.symbol(), newSymbol);
    }

    function test_update_metadata_reverts_if_not_owner() public {
        _deployV4Coin();
        string memory newName = "NewName";
        string memory newSymbol = "NEW";

        vm.expectRevert(abi.encodeWithSelector(MultiOwnable.OnlyOwner.selector));
        coinV4.setNameAndSymbol(newName, newSymbol);
    }

    function test_update_metadata_reverts_if_name_is_blank() public {
        _deployV4Coin();
        string memory newName = "";
        string memory newSymbol = "NEW";

        vm.prank(users.creator);
        vm.expectRevert(abi.encodeWithSelector(ICoin.NameIsRequired.selector));
        coinV4.setNameAndSymbol(newName, newSymbol);
    }

    function test_deploy_coin_with_invalid_parameters() public {
        address[] memory owners = new address[](1);
        owners[0] = users.creator;

        bytes memory poolConfig = CoinConfigurationVersions.defaultDopplerMultiCurveUniV4(address(weth));

        // Test with empty name - should revert
        vm.expectRevert(abi.encodeWithSelector(ICoin.NameIsRequired.selector));
        factory.deploy(
            users.creator,
            owners,
            "https://test.com",
            "", // empty name
            "TEST",
            poolConfig,
            users.platformReferrer,
            address(0),
            bytes(""),
            bytes32(0)
        );

        // Test with zero address payout recipient - should revert
        vm.expectRevert();
        factory.deploy(
            address(0), // zero address payout recipient
            owners,
            "https://test.com",
            "TestCoin",
            "TEST",
            poolConfig,
            users.platformReferrer,
            address(0),
            bytes(""),
            bytes32(0)
        );
    }

    function test_access_control_unauthorized_actions() public {
        _deployV4Coin();

        address unauthorizedUser = makeAddr("unauthorized");

        // Test unauthorized access to owner-only functions
        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(MultiOwnable.OnlyOwner.selector));
        coinV4.setPayoutRecipient(makeAddr("newRecipient"));

        vm.prank(unauthorizedUser);
        vm.expectRevert(abi.encodeWithSelector(MultiOwnable.OnlyOwner.selector));
        coinV4.setContractURI("https://new-uri.com");
    }
}
