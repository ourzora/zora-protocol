// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {ZoraAccountUpgradeGate} from "../src/upgrades/ZoraAccountUpgradeGate.sol";

contract ZoraAccountUpgradeGateTest is Test {
    ZoraAccountUpgradeGate upgradeGate;
    address constant admin = address(0x111);

    function setUp() public {
        upgradeGate = new ZoraAccountUpgradeGate();
        upgradeGate.initialize(admin);
    }

    function test_zoraAccountRegisterUpgrade() public {
        address[] memory contracts = new address[](1);
        contracts[0] = address(0x123);

        vm.prank(admin);
        upgradeGate.registerUpgradePath(contracts, address(0x777));

        assertTrue(upgradeGate.isRegisteredUpgradePath(address(0x123), address(0x777)));
        assertFalse(upgradeGate.isRegisteredUpgradePath(address(0x345), address(0x777)));
    }

    function test_zoraAccountRemoveUpgrade() public {
        address[] memory contracts = new address[](1);
        contracts[0] = address(0x123);

        vm.prank(admin);
        upgradeGate.registerUpgradePath(contracts, address(0x777));
        assertTrue(upgradeGate.isRegisteredUpgradePath(address(0x123), address(0x777)));

        vm.prank(admin);
        upgradeGate.removeUpgradePath(address(0x123), address(0x777));
        assertFalse(upgradeGate.isRegisteredUpgradePath(address(0x123), address(0x777)));
    }
}
