// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {ZoraCreator1155FactoryImpl} from "@zoralabs/zora-1155-contracts/src/factory/ZoraCreator1155FactoryImpl.sol";
import {ZoraCreator1155PremintExecutorImpl} from "@zoralabs/zora-1155-contracts/src/delegation/ZoraCreator1155PremintExecutorImpl.sol";
import {ForkDeploymentConfig, Deployment, ChainConfig} from "../src/DeploymentConfig.sol";
import {ZoraDeployerUtils} from "../src/ZoraDeployerUtils.sol";
import {DeploymentTestingUtils} from "../src/DeploymentTestingUtils.sol";
import {MintArguments, PremintResult} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {IZoraMintsManager} from "@zoralabs/mints-contracts/src/interfaces/IZoraMintsManager.sol";
import {ICollectWithZoraMints} from "@zoralabs/mints-contracts/src/ICollectWithZoraMints.sol";
import {IZoraCreator1155} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155PremintExecutor} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155PremintExecutor.sol";
import {IZoraMints1155Managed} from "@zoralabs/mints-contracts/src/interfaces/IZoraMints1155Managed.sol";
import {ContractCreationConfig, PremintConfigV2} from "@zoralabs/shared-contracts/entities/Premint.sol";

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

interface UUPSUpgradeable {
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable;
}

interface IOwnable2StepUpgradeable {
    function owner() external view returns (address);

    function pendingOwner() external view returns (address);

    function acceptOwnership() external;
}

contract UpgradesTestBase is ForkDeploymentConfig, DeploymentTestingUtils, Test {
    using stdJson for string;

    struct UpgradeStatus {
        string updateDescription;
        bool upgradeNeeded;
        address upgradeTarget;
        address targetImpl;
        bytes upgradeCalldata;
    }

    function determine1155Upgrade(Deployment memory deployment) private view returns (UpgradeStatus memory) {
        address upgradeTarget = deployment.factoryProxy;
        address targetImpl = deployment.factoryImpl;

        bool upgradeNeeded = targetImpl != ZoraCreator1155FactoryImpl(upgradeTarget).implementation();
        bytes memory upgradeCalldata;

        if (upgradeNeeded) {
            upgradeCalldata = ZoraDeployerUtils.getUpgradeCalldata(targetImpl);
        }

        return UpgradeStatus("1155 Factory", upgradeNeeded, upgradeTarget, targetImpl, upgradeCalldata);
    }

    function determinePreminterUpgrade(Deployment memory deployment) private view returns (UpgradeStatus memory) {
        address upgradeTarget = deployment.preminterProxy;
        address targetImpl = deployment.preminterImpl;

        bool upgradeNeeded = targetImpl != ZoraCreator1155PremintExecutorImpl(deployment.preminterProxy).implementation();

        bytes memory upgradeCalldata;
        if (upgradeNeeded) {
            upgradeCalldata = ZoraDeployerUtils.getUpgradeCalldata(targetImpl);
        }

        return UpgradeStatus("Preminter", upgradeNeeded, upgradeTarget, targetImpl, upgradeCalldata);
    }

    function tryReadMintsImpl() private view returns (address mintsImpl) {
        string memory addressPath = string.concat("node_modules/@zoralabs/mints-deployments/addresses/", string.concat(vm.toString(block.chainid), ".json"));
        try vm.readFile(addressPath) returns (string memory result) {
            mintsImpl = result.readAddress(".MINTS_MANAGER_IMPL");
        } catch {}
    }

    function mintsIsDeployed() private view returns (bool) {
        return tryReadMintsImpl() != address(0);
    }

    function determineMintsOwnershipNeeded() private view returns (UpgradeStatus memory) {
        IOwnable2StepUpgradeable mintsManagerProxy = IOwnable2StepUpgradeable(getDeterminsticMintsManagerAddress());

        if (address(mintsManagerProxy).code.length == 0) {
            return UpgradeStatus("Accept Mints Ownership", false, address(0), address(0), "");
        }

        ChainConfig memory chainConfig = getChainConfig();

        bool upgradeNeeded = chainConfig.factoryOwner != mintsManagerProxy.owner();

        bytes memory upgradeCalldata;

        if (upgradeNeeded) {
            if (mintsManagerProxy.pendingOwner() != chainConfig.factoryOwner) {
                revert("Mints pending owner is not the expected owner");
            }
            upgradeCalldata = abi.encodeWithSelector(IOwnable2StepUpgradeable.acceptOwnership.selector);
        }

        return UpgradeStatus("Accept Mints Ownership", upgradeNeeded, address(mintsManagerProxy), address(0), upgradeCalldata);
    }

    function determineMintsUpgrade() private view returns (UpgradeStatus memory) {
        address mintsManagerProxy = getDeterminsticMintsManagerAddress();

        address targetImpl = tryReadMintsImpl();
        if (targetImpl == address(0)) {
            console2.log("Mints not deployed");
            UpgradeStatus memory upgradeStatus;
            return upgradeStatus;
        }

        if (targetImpl.code.length == 0) {
            revert("No code at target impl");
        }

        bool upgradeNeeded = GetImplementation(mintsManagerProxy).implementation() != targetImpl;

        address upgradeTarget = mintsManagerProxy;

        bytes memory upgradeCalldata;

        if (upgradeNeeded) {
            // in the case of transparent proxy - the upgrade target is the proxy admin contract.
            // get upgrade calldata
            upgradeCalldata = abi.encodeWithSelector(UUPSUpgradeable.upgradeToAndCall.selector, targetImpl, "");
        }

        return UpgradeStatus("Mints", upgradeNeeded, upgradeTarget, targetImpl, upgradeCalldata);
    }

    function _buildSafeUrl(address safe, address target, bytes memory cd) internal view returns (string memory) {
        address[] memory targets = new address[](1);
        targets[0] = target;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = cd;

        return _buildBatchSafeUrl(safe, targets, calldatas);
    }

    // pipe delimiter is url encoded | which is %7C
    string constant PIPE_DELIMITER = "%7C";

    function _buildBatchSafeUrl(address safe, address[] memory targets, bytes[] memory cd) internal view returns (string memory) {
        string memory targetsString = "";

        for (uint256 i = 0; i < targets.length; i++) {
            targetsString = string.concat(targetsString, vm.toString(targets[i]));

            if (i < targets.length - 1) {
                targetsString = string.concat(targetsString, PIPE_DELIMITER);
            }
        }

        string memory calldataString = "";

        for (uint256 i = 0; i < cd.length; i++) {
            calldataString = string.concat(calldataString, vm.toString(cd[i]));

            if (i < cd.length - 1) {
                calldataString = string.concat(calldataString, PIPE_DELIMITER);
            }
        }

        string memory valuesString = "";

        for (uint256 i = 0; i < cd.length; i++) {
            valuesString = string.concat(valuesString, "0");

            if (i < cd.length - 1) {
                valuesString = string.concat(valuesString, PIPE_DELIMITER);
            }
        }

        // sample url: https://ourzora.github.io/smol-safe/${chainId}/${safeAddress}&target={pipeDelimitedTargets}&calldata={pipeDelimitedCalldata}&value={pipeDelimitedValues}
        string memory targetUrl = "https://ourzora.github.io/smol-safe/#safe/";
        targetUrl = string.concat(targetUrl, vm.toString(block.chainid));
        targetUrl = string.concat(targetUrl, "/");
        targetUrl = string.concat(targetUrl, vm.toString(safe));
        targetUrl = string.concat(targetUrl, "/new");
        targetUrl = string.concat(targetUrl, "?");
        targetUrl = string.concat(targetUrl, "targets=");
        targetUrl = string.concat(targetUrl, targetsString);
        targetUrl = string.concat(targetUrl, "&calldatas=");
        targetUrl = string.concat(targetUrl, calldataString);
        targetUrl = string.concat(targetUrl, "&values=");
        targetUrl = string.concat(targetUrl, valuesString);

        return targetUrl;
    }

    function getUpgradeCalls(UpgradeStatus[] memory upgradeStatuses) private pure returns (address[] memory upgradeTargets, bytes[] memory upgradeCalldatas) {
        uint256 numberOfUpgrades = 0;
        for (uint256 i = 0; i < upgradeStatuses.length; i++) {
            if (upgradeStatuses[i].upgradeNeeded) {
                numberOfUpgrades++;
            }
        }
        upgradeCalldatas = new bytes[](numberOfUpgrades);
        upgradeTargets = new address[](numberOfUpgrades);
        uint256 currentUpgradeIndex = 0;
        for (uint256 i = 0; i < upgradeStatuses.length; i++) {
            if (upgradeStatuses[i].upgradeNeeded) {
                upgradeCalldatas[currentUpgradeIndex] = upgradeStatuses[i].upgradeCalldata;
                upgradeTargets[currentUpgradeIndex] = upgradeStatuses[i].upgradeTarget;
                currentUpgradeIndex++;

                // print out upgrade info
                console2.log("upgrading: ", upgradeStatuses[i].updateDescription);
                console2.log("target:", upgradeStatuses[i].upgradeTarget);
                console2.log("calldata:", vm.toString(upgradeStatuses[i].upgradeCalldata));
            }
        }
    }

    function performNeededUpgrades(address upgrader, UpgradeStatus[] memory upgradeStatuses) private returns (bool anyUpgradePerformed) {
        vm.startPrank(upgrader);
        for (uint256 i = 0; i < upgradeStatuses.length; i++) {
            UpgradeStatus memory upgradeStatus = upgradeStatuses[i];
            if (upgradeStatus.upgradeNeeded) {
                anyUpgradePerformed = true;
                console2.log("simulating upgrade:", upgradeStatus.updateDescription);
                if (upgradeStatus.upgradeCalldata.length == 0) {
                    revert("upgrade calldata is empty");
                }

                (bool success, ) = upgradeStatus.upgradeTarget.call(upgradeStatus.upgradeCalldata);

                if (!success) {
                    revert("upgrade failed");
                }
            }
        }
        vm.stopPrank();
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

    function checkPremintWithMINTsWorks() private {
        if (!mintsIsDeployed()) {
            console2.log("skipping premint with MINTs test, MINTs not deployed");
            return;
        }
        console2.log("testing collecing premints with MINTs");
        // test premints:
        address collector = makeAddr("collector");
        vm.deal(collector, 10 ether);

        IZoraMintsManager zoraMintsManager = IZoraMintsManager(getDeterminsticMintsManagerAddress());

        address[] memory mintRewardsRecipients = new address[](0);

        MintArguments memory mintArguments = MintArguments({mintRecipient: collector, mintComment: "", mintRewardsRecipients: mintRewardsRecipients});

        uint256 quantityToMint = 5;

        vm.startPrank(collector);

        zoraMintsManager.mintWithEth{value: zoraMintsManager.getEthPrice() * quantityToMint}(quantityToMint, collector);

        uint256[] memory mintTokenIds = new uint256[](1);
        mintTokenIds[0] = zoraMintsManager.mintableEthToken();
        uint256[] memory quantities = new uint256[](1);
        quantities[0] = 3;

        (ContractCreationConfig memory contractConfig, , PremintConfigV2 memory premintConfig, bytes memory signature) = createAndSignPremintV2(
            getDeployment().preminterProxy,
            makeAddr("payoutRecipientG"),
            10_000
        );

        bytes memory call = abi.encodeWithSelector(
            ICollectWithZoraMints.collectPremintV2.selector,
            contractConfig,
            premintConfig,
            signature,
            mintArguments,
            address(0)
        );

        PremintResult memory result = abi.decode(
            IZoraMints1155Managed(address(zoraMintsManager.zoraMints1155())).transferBatchToManagerAndCall(mintTokenIds, quantities, call),
            (PremintResult)
        );

        assertEq(IZoraCreator1155(result.contractAddress).balanceOf(collector, result.tokenId), quantities[0]);

        vm.stopPrank();
    }

    function checkContracts() private {
        checkPremintingWorks();

        checkPremintWithMINTsWorks();
    }

    /// @notice checks which chains need an upgrade, simulated the upgrade, and gets the upgrade calldata
    function simulateUpgrade() internal {
        Deployment memory deployment = getDeployment();

        ChainConfig memory chainConfig = getChainConfig();

        UpgradeStatus[] memory upgradeStatuses = new UpgradeStatus[](4);
        upgradeStatuses[0] = determine1155Upgrade(deployment);
        upgradeStatuses[1] = determinePreminterUpgrade(deployment);
        upgradeStatuses[2] = determineMintsOwnershipNeeded();
        upgradeStatuses[3] = determineMintsUpgrade();

        bool upgradePerformed = performNeededUpgrades(chainConfig.factoryOwner, upgradeStatuses);

        if (upgradePerformed) {
            checkContracts();

            console2.log("---------------");

            (address[] memory upgradeTargets, bytes[] memory upgradeCalldatas) = getUpgradeCalls(upgradeStatuses);

            string memory smolSafeUrl = _buildBatchSafeUrl(chainConfig.factoryOwner, upgradeTargets, upgradeCalldatas);

            console2.log("smol safe url: ", smolSafeUrl);

            console2.log("---------------");
        }
    }
}
