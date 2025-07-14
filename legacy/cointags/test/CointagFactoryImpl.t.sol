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
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockFactoryWithIncorrectName} from "./mocks/MockFactoryWithIncorrectName.sol";
import {IHasContractName} from "@zoralabs/shared-contracts/interfaces/IContractMetadata.sol";
import {ICointagFactory} from "../src/interfaces/ICointagFactory.sol";

contract CointagFactoryImplTest is BaseTest {
    function testCointagFactoryImplContractName() public view {
        assertEq(factory.contractName(), "Cointags Factory");
    }

    function testCointagFactoryImplImplementation() public view {
        assertEq(factory.implementation(), address(factoryImpl));
    }

    function testCointagFactoryImplContractURI() public view {
        assertEq(factory.contractURI(), "https://github.com/ourzora/zora-protocol/");
    }

    function testCointagFactoryUpgrade() public {
        CointagFactoryImpl newImplementation = new CointagFactoryImpl(address(cointag));

        assertEq(factory.implementation(), address(factoryImpl));

        vm.prank(admin);
        factory.upgradeToAndCall(address(newImplementation), "");

        assertEq(factory.implementation(), address(newImplementation));
    }

    function testCointagFactoryUpgradeAdminIncorrect() public {
        CointagFactoryImpl newImplementation = new CointagFactoryImpl(address(cointag));

        assertEq(factory.implementation(), address(factoryImpl));

        address fakeAdmin = address(0x123);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, fakeAdmin));
        vm.prank(fakeAdmin);
        factory.upgradeToAndCall(address(newImplementation), "");
    }

    function testCointagFactoryUpgradeNameMismatch() public {
        address mockImplementation = address(new MockFactoryWithIncorrectName());

        vm.expectRevert(abi.encodeWithSelector(ICointagFactory.UpgradeToMismatchedContractName.selector, "Cointags Factory", "Different Name"));
        vm.prank(admin);
        factory.upgradeToAndCall(address(mockImplementation), "");
    }

    function testCointagFactoryImplGetCointagAddress() public {
        address pool = vm.parseAddress("0x1c251dc66d5259fd1e2d1cf151a83191ca4898d9");
        uint256 buyBurnPercentage = 2000;

        ICointag cointag = factory.getOrCreateCointag(creatorRewardRecipient, pool, buyBurnPercentage, emptyBytes);

        assertEq(factory.getCointagAddress(creatorRewardRecipient, pool, buyBurnPercentage, emptyBytes), address(cointag));
    }

    function testCointagFactoryImplRequireNotAddressZero() public {
        CointagFactoryImpl newFactoryImpl = new CointagFactoryImpl(address(cointag));
        CointagFactoryImpl newFactory = CointagFactoryImpl(address(new CointagFactory(address(newFactoryImpl))));
        address ownerZero = address(0);

        vm.expectRevert(abi.encodeWithSignature("AddressZero()"));
        newFactory.initialize(ownerZero);
    }

    function testGetOrCreateCointagAtExpectedAddress() public {
        address pool = vm.parseAddress("0x1c251dc66d5259fd1e2d1cf151a83191ca4898d9");
        uint256 buyBurnPercentage = 2000;

        // First get the expected address
        address expectedAddress = factory.getCointagAddress(creatorRewardRecipient, pool, buyBurnPercentage, emptyBytes);

        // Create with correct expected address
        ICointag cointag = factory.getOrCreateCointagAtExpectedAddress(creatorRewardRecipient, pool, buyBurnPercentage, emptyBytes, expectedAddress);

        assertEq(address(cointag), expectedAddress);
    }

    function testGetOrCreateCointagAtExpectedAddressReverts() public {
        address pool = vm.parseAddress("0x1c251dc66d5259fd1e2d1cf151a83191ca4898d9");
        uint256 buyBurnPercentage = 2000;
        address wrongExpectedAddress = address(0x123);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICointagFactory.UnexpectedCointagAddress.selector,
                wrongExpectedAddress,
                factory.getCointagAddress(creatorRewardRecipient, pool, buyBurnPercentage, emptyBytes)
            )
        );

        factory.getOrCreateCointagAtExpectedAddress(creatorRewardRecipient, pool, buyBurnPercentage, emptyBytes, wrongExpectedAddress);
    }

    function testUpgradingDoesntChangeAddress() public {
        address pool = vm.parseAddress("0x1c251dc66d5259fd1e2d1cf151a83191ca4898d9");
        uint256 buyBurnPercentage = 2000;

        // Get address with default implementation
        address predictedAddress = factory.getCointagAddress(creatorRewardRecipient, pool, buyBurnPercentage, emptyBytes);

        ICointag cointag = factory.getOrCreateCointag(creatorRewardRecipient, pool, buyBurnPercentage, emptyBytes);

        assertEq(predictedAddress, address(cointag));

        // Deploy new implementation
        CointagImpl newCointag = new CointagImpl(address(protocolRewards), address(weth), address(upgradeGate));
        CointagFactoryImpl newFactoryImpl = new CointagFactoryImpl(address(newCointag));

        // upgrade to new implementation
        vm.prank(admin);
        factory.upgradeToAndCall(address(newFactoryImpl), "");

        // Get address with new implementation - should be different
        address newImplAddressAfterUpgrade = factory.getCointagAddress(creatorRewardRecipient, pool, buyBurnPercentage, emptyBytes);

        assertEq(newImplAddressAfterUpgrade, address(cointag));
    }

    function testConstructorAddressZeroCheck() public {
        vm.expectRevert(abi.encodeWithSelector(ICointagFactory.AddressZero.selector));
        new CointagFactoryImpl(address(0));
    }
}
