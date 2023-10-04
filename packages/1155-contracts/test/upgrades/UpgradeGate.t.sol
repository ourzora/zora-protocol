// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {UpgradeGate} from "../../src/upgrades/UpgradeGate.sol";

contract UpgradeGateTest is Test {
    UpgradeGate upgradeGate;
    address constant admin = address(0x123);

    function setUp() public {
        upgradeGate = new UpgradeGate();
        upgradeGate.initialize(admin);
    }

    function test_AdminOnly() public {
        address[] memory oldContracts = new address[](1);
        oldContracts[0] = address(0x01);

        vm.expectRevert();
        upgradeGate.registerUpgradePath(oldContracts, address(0x99));

        vm.expectRevert();
        upgradeGate.removeUpgradePath(address(0x04), address(0x99));
    }

    function test_registersUpgradePath() public {
        address[] memory oldContracts = new address[](2);
        oldContracts[0] = address(0x04);
        oldContracts[1] = address(0x05);

        vm.prank(admin);
        upgradeGate.registerUpgradePath(oldContracts, address(0x99));

        assertTrue(upgradeGate.isRegisteredUpgradePath(address(0x04), address(0x99)));
        assertTrue(upgradeGate.isRegisteredUpgradePath(address(0x05), address(0x99)));
        assertFalse(upgradeGate.isRegisteredUpgradePath(address(0x01), address(0x99)));
    }

    function test_removesUpgradePath() public {
        address[] memory oldContracts = new address[](2);
        oldContracts[0] = address(0x04);
        oldContracts[1] = address(0x05);

        vm.prank(admin);
        upgradeGate.registerUpgradePath(oldContracts, address(0x99));
        assertTrue(upgradeGate.isRegisteredUpgradePath(address(0x04), address(0x99)));
        vm.prank(admin);
        upgradeGate.removeUpgradePath(address(0x04), address(0x99));
        assertFalse(upgradeGate.isRegisteredUpgradePath(address(0x04), address(0x99)));
    }
}
