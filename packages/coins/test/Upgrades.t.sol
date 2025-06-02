// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import {Test} from "forge-std/Test.sol";
import {IZoraFactory} from "../src/interfaces/IZoraFactory.sol";
import {ZoraFactoryImpl} from "../src/ZoraFactoryImpl.sol";
import {BaseTest} from "./utils/BaseTest.sol";

contract BadImpl {
    function contractName() public pure returns (string memory) {
        return "BadImpl";
    }
}

contract UpgradesTest is BaseTest {
    ZoraFactoryImpl public factoryProxy;

    function test_canUpgradeFromVersionWithoutContractName() public {
        // this test that we can upgrade from the current version, which doesn't have a contract name
        vm.createSelectFork("base", 29675508);

        factoryProxy = ZoraFactoryImpl(0x777777751622c0d3258f214F9DF38E35BF45baF3);

        ZoraFactoryImpl newImpl = new ZoraFactoryImpl(factoryProxy.coinImpl(), address(coinV4Impl));

        vm.prank(factoryProxy.owner());
        factoryProxy.upgradeToAndCall(address(newImpl), "");

        assertEq(factoryProxy.implementation(), address(newImpl));
    }

    function test_cannotUpgradeToMismatchedContractName() public {
        // this test that we cannot upgrade to a contract with a mismatched contract name
        // once we have upgraded to the version that checks the contract name when upgrading
        vm.createSelectFork("base", 29675508);

        factoryProxy = ZoraFactoryImpl(0x777777751622c0d3258f214F9DF38E35BF45baF3);

        ZoraFactoryImpl newImpl = new ZoraFactoryImpl(factoryProxy.coinImpl(), address(coinV4Impl));

        vm.prank(factoryProxy.owner());
        factoryProxy.upgradeToAndCall(address(newImpl), "");

        BadImpl badImpl = new BadImpl();

        vm.prank(factoryProxy.owner());
        vm.expectRevert(abi.encodeWithSelector(IZoraFactory.UpgradeToMismatchedContractName.selector, "ZoraCoinFactory", "BadImpl"));
        factoryProxy.upgradeToAndCall(address(badImpl), "");
    }

    function test_canUpgradeToSameContractName() public {
        // this test that we can upgrade to the same contract name, when we have already upgraded to a version that has a contract name
        vm.createSelectFork("base", 29675508);

        factoryProxy = ZoraFactoryImpl(0x777777751622c0d3258f214F9DF38E35BF45baF3);

        ZoraFactoryImpl newImpl = new ZoraFactoryImpl(factoryProxy.coinImpl(), address(coinV4Impl));

        vm.prank(factoryProxy.owner());
        factoryProxy.upgradeToAndCall(address(newImpl), "");

        ZoraFactoryImpl newImpl2 = new ZoraFactoryImpl(factoryProxy.coinImpl(), factoryProxy.coinV4Impl());

        vm.prank(factoryProxy.owner());
        factoryProxy.upgradeToAndCall(address(newImpl2), "");

        assertEq(factoryProxy.implementation(), address(newImpl2));
    }
}
