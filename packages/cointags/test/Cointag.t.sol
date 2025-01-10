// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {CointagFactoryImpl} from "../src/CointagFactoryImpl.sol";
import {CointagImpl} from "../src/CointagImpl.sol";
import {CointagFactory} from "../src/proxy/CointagFactory.sol";
import {IWETH} from "@zoralabs/shared-contracts/interfaces/IWETH.sol";
import {IProtocolRewards} from "@zoralabs/shared-contracts/interfaces/IProtocolRewards.sol";
import {IUniswapV3Pool} from "@zoralabs/shared-contracts/interfaces/uniswap/IUniswapV3Pool.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ISwapRouter} from "@zoralabs/shared-contracts/interfaces/uniswap/ISwapRouter.sol";
import {ICointag} from "../src/interfaces/ICointag.sol";
import {ERC1967Utils} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BaseTest} from "./BaseTest.sol";
import {IBurnableERC20} from "../src/interfaces/IBurnableERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MockContractWithName} from "./mocks/MockContractWithName.sol";
import {UpgradeGate} from "../src/upgrades/UpgradeGate.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract CointagTest is BaseTest {
    function test_canPullAndBuyBurn() public {
        // lets try setting up with this popular a weth/moodang pool on base-sepolia
        address pool = vm.parseAddress("0x1c251dc66d5259fd1e2d1cf151a83191ca4898d9");

        // lets setup with a buyBurn percentage of 20%
        uint256 buyBurnPercentage = 2000;

        uint256 amountToDeposit = 1 ether;

        // lets create the cointag
        ICointag cointag = factory.getOrCreateCointag(creatorRewardRecipient, pool, buyBurnPercentage, emptyBytes);

        // lets deposit the amount to the protocol rewards contract - will leave the reasons blank
        protocolRewards.deposit{value: amountToDeposit}(address(cointag), 0, "");

        // now lets call pull on the cointag
        cointag.pull();

        // ensure that the creator received amount - burn percentage
        uint256 amountToCreator = (amountToDeposit * (10_000 - buyBurnPercentage)) / 10_000;
        assertEq(protocolRewards.balanceOf(creatorRewardRecipient), amountToCreator);
    }

    function test_canPushToReceive() public {
        // lets try setting up with this popular a weth/moodang pool on base-sepolia
        address pool = vm.parseAddress("0x1c251dc66d5259fd1e2d1cf151a83191ca4898d9");

        // lets setup with a buyBurn percentage of 20%
        uint256 buyBurnPercentage = 2000;

        ICointag cointag = factory.getOrCreateCointag(creatorRewardRecipient, address(pool), buyBurnPercentage, emptyBytes);

        // lets deposit the amount to the protocol rewards contract - will leave the reasons blank
        uint256 amountToDeposit = 1 ether;
        vm.expectEmit(true, true, true, false);
        emit ICointag.EthReceived(amountToDeposit, address(this));
        (bool success, ) = payable(address(cointag)).call{value: amountToDeposit}("");
        require(success, "Deposit failed");

        // now lets call distribute on the cointag
        cointag.distribute();

        uint256 amountToCreator = (amountToDeposit * (10_000 - buyBurnPercentage)) / 10_000;
        assertEq(protocolRewards.balanceOf(creatorRewardRecipient), amountToCreator);
        assertEq(address(cointag).balance, 0);
    }

    function test_SwapWithWETHAsToken1Pair() public {
        setupBaseFork();

        IUniswapV3Pool pool = IUniswapV3Pool(vm.parseAddress("0x316F12517630903035A0E0B4D6E617593EE432ba"));
        assertEq(pool.token1(), address(weth));
        ICointag cointag = factory.getOrCreateCointag(creatorRewardRecipient, address(pool), 2000, emptyBytes);

        protocolRewards.deposit{value: 1 ether}(address(cointag), 0, "");

        vm.expectEmit(true, true, true, false);
        emit ICointag.BuyBurn(
            0,
            0,
            200000000000000000,
            1000000000000000000,
            1000000000000000000,
            hex"08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000353504c0000000000000000000000000000000000000000000000000000000000",
            new bytes(0)
        );

        cointag.pull();

        uint256 amountToBuyBurn = (1 ether * 2000) / 10_000;
        uint256 amountToSendToCreator = 1 ether - amountToBuyBurn;

        assertEq(protocolRewards.balanceOf(creatorRewardRecipient), amountToSendToCreator, "creator reward recipient balance");
    }

    function test_FailNonUniswapV3Pool() public {
        setupBaseFork();

        // this is a uniswap v2 pool - it should revert
        IUniswapV3Pool pool = IUniswapV3Pool(vm.parseAddress("0x6d6391B9bD02Eefa00FA711fB1Cb828A6471d283"));
        vm.expectRevert(abi.encodeWithSelector(ICointag.NotUniswapV3Pool.selector));
        factory.getOrCreateCointag(creatorRewardRecipient, address(pool), 2000, emptyBytes);
    }

    // Helper function to get current price from pool
    function getPrice(address _pool) internal view returns (uint256) {
        return IUniswapV3Pool(_pool).slot0().sqrtPriceX96;
    }

    function testBuyFailure() public {
        address pool = vm.parseAddress("0x1c251dc66d5259fd1e2d1cf151a83191ca4898d9");

        uint256 buyBurnPercentage = 2000;
        uint256 amountToDeposit = 1 ether;

        ICointag cointag = factory.getOrCreateCointag(creatorRewardRecipient, pool, buyBurnPercentage, emptyBytes);

        protocolRewards.deposit{value: amountToDeposit}(address(cointag), 0, "");

        bytes memory errorData = abi.encodeWithSignature("Error(string)", "Swap failed");
        vm.mockCallRevert(
            pool,
            abi.encodeWithSelector(
                IUniswapV3Pool.swap.selector,
                address(cointag),
                true,
                (amountToDeposit * buyBurnPercentage) / 10_000,
                4295128740,
                new bytes(0)
            ),
            errorData
        );
        vm.expectEmit(true, true, true, true);
        emit ICointag.BuyBurn(
            0,
            0,
            200000000000000000,
            1000000000000000000,
            1000000000000000000,
            hex"08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000b53776170206661696c6564000000000000000000000000000000000000000000",
            new bytes(0)
        );
        cointag.pull();

        uint256 amountToBuyBurn = (amountToDeposit * buyBurnPercentage) / 10_000;
        uint256 amountToSendToCreator = amountToDeposit - amountToBuyBurn;

        assertEq(address(cointag).balance, 0);
        assertEq(protocolRewards.balanceOf(creatorRewardRecipient), amountToSendToCreator);
        // weth balance should be what was supposed to be bought and burned
        assertEq(weth.balanceOf(creatorRewardRecipient), amountToBuyBurn);
    }

    function testBurnFailure() public {
        IUniswapV3Pool pool = IUniswapV3Pool(vm.parseAddress("0x1c251dc66d5259fd1e2d1cf151a83191ca4898d9"));

        uint256 buyBurnPercentage = 2000;
        uint256 amountToDeposit = 1 ether;
        ICointag cointag = factory.getOrCreateCointag(creatorRewardRecipient, address(pool), buyBurnPercentage, emptyBytes);

        protocolRewards.deposit{value: amountToDeposit}(address(cointag), 0, "");

        // mock the swap that returns x amount of
        uint256 mockErc20Received = 1_000_000_000 * 10 ** 18;
        // mock the swap that returns x amount of
        uint256 buyBurnAmount = (amountToDeposit * buyBurnPercentage) / 10_000;

        // mock amount 0 and amount 1
        // mock out should be negative erc20 received
        int256 amount0 = pool.token0() == address(weth) ? int256(buyBurnAmount) : -int256(mockErc20Received);
        int256 amount1 = pool.token1() == address(weth) ? int256(buyBurnAmount) : -int256(mockErc20Received);

        vm.mockCall(
            address(pool),
            0,
            abi.encodeWithSelector(IUniswapV3Pool.swap.selector, address(cointag), true, buyBurnAmount, 4295128740, new bytes(0)),
            abi.encode(amount0, amount1)
        );

        address erc20 = pool.token0() == address(weth) ? pool.token1() : pool.token0();

        vm.mockCall(erc20, abi.encodeWithSelector(IERC20.balanceOf.selector, address(cointag)), abi.encode(mockErc20Received));

        bytes memory burnError = abi.encodeWithSignature("Error(string)", "Burn failed");
        vm.mockCallRevert(erc20, abi.encodeWithSelector(IBurnableERC20.burn.selector, mockErc20Received), burnError);

        address deadAddress = 0x000000000000000000000000000000000000dEaD;

        // if burn fails, it should mock call to transfer the erc20 to the dead address to be successfully transferred
        vm.mockCall(address(erc20), 0, abi.encodeWithSelector(IERC20.transfer.selector, deadAddress, mockErc20Received), abi.encode(true));

        vm.expectEmit(true, true, true, true);
        emit ICointag.BuyBurn({
            amountERC20Received: mockErc20Received,
            amountERC20Burned: mockErc20Received,
            amountETHSpent: buyBurnAmount,
            amountETHToCreator: amountToDeposit - buyBurnAmount,
            totalETHReceived: amountToDeposit,
            buyFailureError: new bytes(0),
            burnFailureError: burnError
        });
        cointag.pull();

        // make sure creator has the amount not burned
        assertEq(protocolRewards.balanceOf(creatorRewardRecipient), amountToDeposit - buyBurnAmount);
    }

    function testBurnAndTransferFailure() public {
        IUniswapV3Pool pool = IUniswapV3Pool(vm.parseAddress("0x1c251dc66d5259fd1e2d1cf151a83191ca4898d9"));

        uint256 buyBurnPercentage = 2000;
        uint256 amountToDeposit = 1 ether;
        ICointag cointag = factory.getOrCreateCointag(creatorRewardRecipient, address(pool), buyBurnPercentage, emptyBytes);

        protocolRewards.deposit{value: amountToDeposit}(address(cointag), 0, "");

        // mock the swap that returns x amount of
        uint256 mockErc20Received = 1_000_000_000 * 10 ** 18;
        uint256 buyBurnAmount = (amountToDeposit * buyBurnPercentage) / 10_000;

        // Mock successful swap
        int256 amount0 = pool.token0() == address(weth) ? int256(buyBurnAmount) : -int256(mockErc20Received);
        int256 amount1 = pool.token1() == address(weth) ? int256(buyBurnAmount) : -int256(mockErc20Received);

        vm.mockCall(
            address(pool),
            0,
            abi.encodeWithSelector(IUniswapV3Pool.swap.selector, address(cointag), true, buyBurnAmount, 4295128740, new bytes(0)),
            abi.encode(amount0, amount1)
        );

        address erc20 = pool.token0() == address(weth) ? pool.token1() : pool.token0();

        vm.mockCall(erc20, abi.encodeWithSelector(IERC20.balanceOf.selector, address(cointag)), abi.encode(mockErc20Received));

        // Mock burn failure
        bytes memory burnError = abi.encodeWithSignature("Error(string)", "Burn failed");
        vm.mockCallRevert(erc20, abi.encodeWithSelector(IBurnableERC20.burn.selector, mockErc20Received), burnError);

        // Mock transfer failure
        bytes memory transferError = abi.encodeWithSignature("Error(string)", "Transfer failed");
        address DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
        vm.mockCallRevert(erc20, abi.encodeWithSelector(IERC20.transfer.selector, DEAD_ADDRESS, mockErc20Received), transferError);

        vm.expectEmit(true, true, true, true);
        emit ICointag.BuyBurn({
            amountERC20Received: mockErc20Received,
            amountERC20Burned: 0, // No tokens burned since both burn and transfer failed
            amountETHSpent: buyBurnAmount,
            amountETHToCreator: amountToDeposit - buyBurnAmount,
            totalETHReceived: amountToDeposit,
            buyFailureError: new bytes(0),
            burnFailureError: transferError // Final error should be from the transfer attempt
        });

        cointag.pull();

        // make sure creator has the amount not burned
        assertEq(protocolRewards.balanceOf(creatorRewardRecipient), (1 ether * (10_000 - buyBurnPercentage)) / 10_000);
    }

    function testConstructorAddressZeroChecks() public {
        vm.expectRevert(abi.encodeWithSelector(ICointag.AddressZero.selector));
        new CointagImpl(address(0), address(weth), address(upgradeGate));

        vm.expectRevert(abi.encodeWithSelector(ICointag.AddressZero.selector));
        new CointagImpl(address(protocolRewards), address(0), address(upgradeGate));

        vm.expectRevert(abi.encodeWithSelector(ICointag.AddressZero.selector));
        new CointagImpl(address(protocolRewards), address(weth), address(0));
    }

    function testInitializeAddressZeroChecks() public {
        IUniswapV3Pool pool = IUniswapV3Pool(vm.parseAddress("0x1c251dc66d5259fd1e2d1cf151a83191ca4898d9"));
        vm.expectRevert(abi.encodeWithSelector(ICointag.AddressZero.selector));
        factory.getOrCreateCointag(address(0), address(pool), 2000, emptyBytes);

        vm.expectRevert(abi.encodeWithSelector(ICointag.AddressZero.selector));
        factory.getOrCreateCointag(address(protocolRewards), address(0), 2000, emptyBytes);
    }

    function testInitializeWETHPoolCheck() public {
        IUniswapV3Pool pool = IUniswapV3Pool(vm.parseAddress("0xB3f298f9A6C3f0b60453cfCEaB96ECd5fdD1E005"));

        vm.expectRevert(abi.encodeWithSelector(ICointag.PoolNeedsOneTokenToBeWETH.selector));
        factory.getOrCreateCointag(creatorRewardRecipient, address(pool), 2000, emptyBytes);
    }

    function test_upgrade_succeeds_whenValidPathAndName() public {
        // Setup initial cointag
        address pool = vm.parseAddress("0x1c251dc66d5259fd1e2d1cf151a83191ca4898d9");
        ICointag cointag = factory.getOrCreateCointag(creatorRewardRecipient, pool, 2000, emptyBytes);

        assertEq(cointag.config().creatorRewardRecipient, creatorRewardRecipient);
        assertEq(address(cointag.config().pool), pool);
        assertEq(cointag.config().percentageToBuyBurn, 2000);

        assertEq(address(cointag.pool()), pool);
        assertEq(address(cointag.erc20()), address(0xc4B164B556eBe1eEF68614e47dF3B063a2E2c276));

        // Deploy new implementation
        CointagImpl newImpl = new CointagImpl(address(protocolRewards), address(weth), address(upgradeGate));

        // Register upgrade path
        address[] memory oldImpls = new address[](1);
        oldImpls[0] = cointag.implementation();
        vm.prank(UpgradeGate(address(upgradeGate)).owner());
        upgradeGate.registerUpgradePath(oldImpls, address(newImpl));

        // Perform upgrade
        vm.prank(creatorRewardRecipient); // Creator is owner
        UUPSUpgradeable(address(cointag)).upgradeToAndCall(address(newImpl), "");

        // Verify upgrade succeeded
        assertEq(cointag.implementation(), address(newImpl));
    }

    function test_upgrade_reverts_whenContractNameMismatch() public {
        // Setup initial cointag
        address pool = vm.parseAddress("0x1c251dc66d5259fd1e2d1cf151a83191ca4898d9");
        ICointag cointag = factory.getOrCreateCointag(creatorRewardRecipient, pool, 2000, emptyBytes);

        // Deploy mock implementation with wrong name
        MockContractWithName wrongNameImpl = new MockContractWithName("WrongName");

        // Register upgrade path
        vm.prank(creatorRewardRecipient);
        vm.expectRevert(abi.encodeWithSelector(ICointag.UpgradeToMismatchedContractName.selector, "Cointag", "WrongName"));
        UUPSUpgradeable(payable(address(cointag))).upgradeToAndCall(address(wrongNameImpl), "");
    }

    function test_upgrade_reverts_whenUpgradePathNotRegistered() public {
        // Setup initial cointag
        address pool = vm.parseAddress("0x1c251dc66d5259fd1e2d1cf151a83191ca4898d9");
        ICointag cointag = factory.getOrCreateCointag(creatorRewardRecipient, pool, 2000, emptyBytes);

        // Deploy new implementation without registering upgrade path
        CointagImpl newImpl = new CointagImpl(address(protocolRewards), address(weth), address(upgradeGate));

        // Attempt upgrade - should revert
        vm.expectRevert(abi.encodeWithSelector(ICointag.InvalidUpgradePath.selector, cointag.implementation(), address(newImpl)));
        vm.prank(creatorRewardRecipient);
        UUPSUpgradeable(payable(address(cointag))).upgradeToAndCall(address(newImpl), "");
    }
}
