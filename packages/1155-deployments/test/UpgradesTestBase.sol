// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ZoraCreator1155FactoryImpl} from "@zoralabs/zora-1155-contracts/src/factory/ZoraCreator1155FactoryImpl.sol";
import {ZoraCreator1155PremintExecutorImpl} from "@zoralabs/zora-1155-contracts/src/delegation/ZoraCreator1155PremintExecutorImpl.sol";
import {DeploymentConfig, Deployment, ChainConfig} from "@zoralabs/zora-1155-contracts/src/deployment/DeploymentConfig.sol";
import {ForkDeploymentConfig} from "@zoralabs/shared-contracts/deployment/ForkDeploymentConfig.sol";
import {UpgradeBaseLib} from "@zoralabs/shared-contracts/upgrades/UpgradeBaseLib.sol";
import {DeploymentTestingUtils} from "@zoralabs/zora-1155-contracts/src/deployment/DeploymentTestingUtils.sol";
import {MintArguments, PremintResult} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {IZoraSparksManager} from "@zoralabs/sparks-contracts/src/interfaces/IZoraSparksManager.sol";
import {IZoraCreator1155} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155.sol";
import {ContractCreationConfig, PremintConfigV2} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {UpgradeGate} from "@zoralabs/zora-1155-contracts/src/upgrades/UpgradeGate.sol";
import {IVersionedContract} from "@zoralabs/shared-contracts/interfaces/IVersionedContract.sol";

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

interface UUPSUpgradeable {
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}

interface IOwnable2StepUpgradeable {
    function owner() external view returns (address);

    function pendingOwner() external view returns (address);

    function acceptOwnership() external;
}

contract UpgradesTestBase is ForkDeploymentConfig, DeploymentTestingUtils, Test, UpgradeBaseLib, DeploymentConfig {
    using stdJson for string;

    function determine1155Upgrade(Deployment memory deployment) private view returns (UpgradeStatus memory) {
        address upgradeTarget = deployment.factoryProxy;
        address targetImpl = deployment.factoryImpl;

        bool upgradeNeeded = targetImpl != ZoraCreator1155FactoryImpl(upgradeTarget).implementation();
        bytes memory upgradeCalldata;

        if (upgradeNeeded) {
            upgradeCalldata = getUpgradeCalldata(targetImpl);
        }

        return UpgradeStatus("1155 Factory", upgradeNeeded, upgradeTarget, targetImpl, upgradeCalldata);
    }

    function determinePreminterUpgrade(Deployment memory deployment) private view returns (UpgradeStatus memory) {
        address upgradeTarget = deployment.preminterProxy;
        address targetImpl = deployment.preminterImpl;

        bool upgradeNeeded = targetImpl != ZoraCreator1155PremintExecutorImpl(deployment.preminterProxy).implementation();

        bytes memory upgradeCalldata;
        if (upgradeNeeded) {
            upgradeCalldata = getUpgradeCalldata(targetImpl);
        }

        return UpgradeStatus("Preminter", upgradeNeeded, upgradeTarget, targetImpl, upgradeCalldata);
    }

    function tryReadImpl(string memory packageName, string memory keyName) private view returns (address impl) {
        string memory addressPath = string.concat("../", packageName, "/addresses/", vm.toString(block.chainid), ".json");
        try vm.readFile(addressPath) returns (string memory result) {
            impl = result.readAddress(string.concat(".", keyName));
        } catch {}
    }

    function determineUpgrade(string memory name, address proxy, string memory packageName, string memory implKey) private view returns (UpgradeStatus memory) {
        address targetImpl = tryReadImpl(packageName, implKey);
        if (targetImpl == address(0)) {
            console2.log(string.concat(name, " not deployed"));
            return UpgradeStatus("", false, address(0), address(0), "");
        }

        if (targetImpl.code.length == 0) {
            revert(string.concat("No code at target impl for ", name));
        }

        bool upgradeNeeded = UpgradeBaseLib.getUpgradeNeeded(proxy, targetImpl);

        bytes memory upgradeCalldata;
        if (upgradeNeeded) {
            upgradeCalldata = abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, targetImpl, "");
        }

        return UpgradeStatus(name, upgradeNeeded, proxy, targetImpl, upgradeCalldata);
    }

    function determineSparksUpgrade() private view returns (UpgradeStatus memory) {
        address mintsManagerProxy = getDeterminsticSparksManagerAddress();
        return determineUpgrade("Sparks", mintsManagerProxy, "sparks-deployments", "SPARKS_MANAGER_IMPL");
    }

    function determineCommentsUpgrade() private view returns (UpgradeStatus memory) {
        address commentsProxy = tryReadImpl("comments", "COMMENTS");
        return determineUpgrade("Comments", commentsProxy, "comments", "COMMENTS_IMPL");
    }

    function determineCallerAndCommenterUpgrade() private view returns (UpgradeStatus memory) {
        address callerAndCommenterProxy = tryReadImpl("comments", "CALLER_AND_COMMENTER");
        return determineUpgrade("CallerAndCommenter", callerAndCommenterProxy, "comments", "CALLER_AND_COMMENTER_IMPL");
    }

    function determintZoraTimedSaleStrategyUpgrade() private view returns (UpgradeStatus memory) {
        address timedSaleStrategyProxy = getDeterminsticZoraTimedSaleStrategyAddress();
        return determineUpgrade("Zora Timed Sale Strategy", timedSaleStrategyProxy, "erc20z", "SALE_STRATEGY_IMPL");
    }

    function checkPremintingWorks() private {
        console2.log("testing preminting");
        // test premints:
        address collector = makeAddr("collector");
        address mintReferral = makeAddr("referral");
        vm.deal(collector, 10 ether);

        address preminterProxy = getDeployment().preminterProxy;

        address[] memory mintRewardsRecipients = new address[](1);
        mintRewardsRecipients[0] = mintReferral;

        MintArguments memory mintArguments = MintArguments({mintRecipient: collector, mintComment: "", mintRewardsRecipients: mintRewardsRecipients});

        vm.startPrank(collector);
        signAndExecutePremintV1(preminterProxy, makeAddr("payoutRecipientA"), mintArguments);
        signAndExecutePremintV2(preminterProxy, makeAddr("payoutRecipientB"), mintArguments);

        vm.stopPrank();
    }

    function checkContracts() private {
        checkPremintingWorks();
    }

    function checkRegisterUpgradePaths() private returns (address[] memory upgradePathTargets, bytes[] memory upgradePathCalls) {
        (upgradePathTargets, upgradePathCalls) = readMissingUpgradePaths();

        if (upgradePathTargets.length > 0) {
            for (uint256 i = 0; i < upgradePathTargets.length; i++) {
                vm.prank(UpgradeGate(upgradePathTargets[i]).owner());
                (bool success, ) = upgradePathTargets[i].call(upgradePathCalls[i]);

                if (!success) {
                    revert("upgrade path failed");
                }
            }
        } else {
            console2.log("no missing upgrade paths");
        }
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
        Deployment memory deployment = getDeployment();

        ChainConfig memory chainConfig = getChainConfig();

        UpgradeStatus[] memory upgradeStatuses = new UpgradeStatus[](6);
        upgradeStatuses[0] = determine1155Upgrade(deployment);
        upgradeStatuses[1] = determinePreminterUpgrade(deployment);
        upgradeStatuses[2] = determineSparksUpgrade();
        upgradeStatuses[3] = determineCommentsUpgrade();
        upgradeStatuses[4] = determineCallerAndCommenterUpgrade();
        upgradeStatuses[5] = determintZoraTimedSaleStrategyUpgrade();

        bool upgradePerformed = performNeededUpgrades(chainConfig.factoryOwner, upgradeStatuses);

        (address[] memory upgradePathTargets, bytes[] memory upgradePathCalls) = checkRegisterUpgradePaths();

        upgradeStatuses = appendCalls(upgradeStatuses, upgradePathTargets, upgradePathCalls, "Register Upgrade Paths");

        (address[] memory upgradeTargets, bytes[] memory upgradeCalldatas) = getUpgradeCalls(upgradeStatuses);

        if (upgradePerformed || upgradeTargets.length > 0) {
            checkContracts();

            console2.log("---------------");

            string memory smolSafeUrl = buildBatchSafeUrl(chainConfig.factoryOwner, upgradeTargets, upgradeCalldatas);

            console2.log("smol safe url: ", smolSafeUrl);

            console2.log("---------------");
        }
    }
}
