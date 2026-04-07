// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ForkDeploymentConfig} from "@zoralabs/shared-contracts/deployment/ForkDeploymentConfig.sol";
import {UpgradeBaseLib} from "@zoralabs/shared-contracts/upgrades/UpgradeBaseLib.sol";

import {IZora1155} from "../../src/interfaces/IZora1155.sol";
import {IZoraTimedSaleStrategy} from "../../src/interfaces/IZoraTimedSaleStrategy.sol";
import {IZoraCreator1155Factory} from "@zoralabs/zora-1155-contracts/interfaces/IZoraCreator1155Factory.sol";
import {ICreatorRoyaltiesControl} from "@zoralabs/zora-1155-contracts/interfaces/ICreatorRoyaltiesControl.sol";
import {DeployerBase} from "../../script/DeployerBase.sol";

interface IERC1967 {
    /**
     * @dev Emitted when the implementation is upgraded.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Emitted when the beacon is changed.
     */
    event BeaconUpgraded(address indexed beacon);
}

interface ITransparentUpgradeableProxy is IERC1967 {
    function upgradeToAndCall(address, bytes calldata) external payable;
}

interface IProxyAdmin {
    function upgradeAndCall(ITransparentUpgradeableProxy proxy, address implementation, bytes memory data) external payable;
}

interface GetImplementation {
    function implementation() external view returns (address);
}

interface IOwner {
    function owner() external view returns (address);
}

interface UUPSUpgradeable {
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}

interface IOwnable2StepUpgradeable {
    function owner() external view returns (address);

    function pendingOwner() external view returns (address);

    function acceptOwnership() external;
}

contract UpgradesTestBase is ForkDeploymentConfig, Test, UpgradeBaseLib, DeployerBase {
    using stdJson for string;

    function determineMinterUpgrade(DeploymentConfig memory deployment) private view returns (UpgradeStatus memory) {
        address upgradeTarget = deployment.saleStrategy;
        address targetImpl = deployment.saleStrategyImpl;

        address currentImplAddress = address(uint160(uint256(vm.load(upgradeTarget, 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc))));
        bool upgradeNeeded = targetImpl != currentImplAddress;

        bytes memory upgradeCalldata;

        if (upgradeNeeded) {
            upgradeCalldata = getUpgradeAndCallCalldata(targetImpl, "");
        }

        return UpgradeStatus("ERC20 Minter Upgrade", upgradeNeeded, upgradeTarget, targetImpl, upgradeCalldata);
    }

    function checkMintingIntegrationWorks(address erc20zSaleStrategy) private {
        address collector = makeAddr("collector");
        address creator = makeAddr("creator");
        vm.deal(collector, 10 ether);

        address zora1155FactoryAddress = vm.parseJsonAddress(
            vm.readFile(string.concat("../1155-contracts/addresses/", vm.toString(block.chainid), ".json")),
            ".FACTORY_PROXY"
        );

        bytes[] memory setupActions = new bytes[](0);
        IZora1155 newContract = IZora1155(
            IZoraCreator1155Factory(zora1155FactoryAddress).createContract(
                "",
                "",
                ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyMintSchedule: 0, royaltyBPS: 0, royaltyRecipient: creator}),
                payable(creator),
                setupActions
            )
        );

        vm.prank(creator);
        uint256 newTokenId = newContract.setupNewToken("", type(uint256).max);

        vm.prank(creator);
        newContract.addPermission(newTokenId, erc20zSaleStrategy, 4);

        assertEq(erc20zSaleStrategy, address(0x777777722D078c97c6ad07d9f36801e653E356Ae));

        vm.prank(creator);
        newContract.callSale(
            newTokenId,
            erc20zSaleStrategy,
            abi.encodeWithSelector(
                IZoraTimedSaleStrategy.setSaleV2.selector,
                newTokenId,
                IZoraTimedSaleStrategy.SalesConfigV2({saleStart: 0, marketCountdown: 60, minimumMarketEth: 0.0000112 ether, name: "testing", symbol: "testing"})
            )
        );

        vm.prank(collector);
        IZoraTimedSaleStrategy(erc20zSaleStrategy).mint{value: 0.000111 ether * 1000}(collector, 1000, address(newContract), newTokenId, address(0), "");

        vm.warp(block.timestamp + 1120);

        IZoraTimedSaleStrategy(erc20zSaleStrategy).launchMarket(address(newContract), newTokenId);

        assertEq(newContract.balanceOf(collector, newTokenId), 1000);

        vm.stopPrank();
    }

    function appendCalls(
        UpgradeStatus[] memory upgradeStatuses,
        address[] memory targets,
        bytes[] memory calls,
        string memory upgradePathDescription
    ) private pure returns (UpgradeStatus[] memory newUpgradeStatuses) {
        newUpgradeStatuses = new UpgradeStatus[](upgradeStatuses.length + targets.length);

        for (uint256 i = 0; i < upgradeStatuses.length; i++) {
            newUpgradeStatuses[i] = upgradeStatuses[i];
        }

        for (uint256 i = 0; i < targets.length; i++) {
            newUpgradeStatuses[upgradeStatuses.length + i] = UpgradeStatus(upgradePathDescription, true, targets[i], address(0), calls[i]);
        }

        return newUpgradeStatuses;
    }

    /// @notice checks which chains need an upgrade, simulated the upgrade, and gets the upgrade calldata
    function simulateUpgrade() internal {
        DeploymentConfig memory deployment = readDeployment();

        UpgradeStatus[] memory upgradeStatuses = new UpgradeStatus[](4);
        UpgradeStatus memory upgradeMinter = determineMinterUpgrade(deployment);
        upgradeStatuses[0] = upgradeMinter;

        address owner = IOwner(deployment.saleStrategy).owner();

        bool upgradePerformed = performNeededUpgrades(owner, upgradeStatuses);

        (address[] memory upgradeTargets, bytes[] memory upgradeCalldatas) = getUpgradeCalls(upgradeStatuses);

        if (upgradePerformed || upgradeTargets.length > 0) {
            checkMintingIntegrationWorks(deployment.saleStrategy);

            console2.log("---------------");

            string memory smolSafeUrl = buildBatchSafeUrl(owner, upgradeTargets, upgradeCalldatas);

            console2.log("smol safe url: ", smolSafeUrl);

            console2.log("---------------");
        }
    }
}
