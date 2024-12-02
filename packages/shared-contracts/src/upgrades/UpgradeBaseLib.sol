// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {CommonBase} from "forge-std/Base.sol";
import {console2, stdJson} from "forge-std/Script.sol";
import {IVersionedContract} from "../interfaces/IVersionedContract.sol";

interface UUPSUpgradeableUpgradeTo {
    function upgradeTo(address) external;

    function upgradeToAndCall(address, bytes calldata) external;
}

interface GetImplementation {
    function implementation() external view returns (address);
}

contract UpgradeBaseLib is CommonBase {
    using stdJson for string;

    struct UpgradeStatus {
        string updateDescription;
        bool upgradeNeeded;
        address upgradeTarget;
        address targetImpl;
        bytes upgradeCalldata;
    }
    // pipe delimiter is url encoded | which is %7C
    string constant PIPE_DELIMITER = "%7C";

    function getUpgradeCalls(UpgradeStatus[] memory upgradeStatuses) internal pure returns (address[] memory upgradeTargets, bytes[] memory upgradeCalldatas) {
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

    function buildSafeUrl(address safe, address target, bytes memory cd) internal view returns (string memory) {
        address[] memory targets = new address[](1);
        targets[0] = target;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = cd;

        return buildBatchSafeUrl(safe, targets, calldatas);
    }

    function buildBatchSafeUrl(address safe, address[] memory targets, bytes[] memory cd) internal view returns (string memory) {
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

    function getUpgradeCalldata(address targetImpl) internal pure returns (bytes memory upgradeCalldata) {
        // simulate upgrade call
        upgradeCalldata = abi.encodeWithSelector(UUPSUpgradeableUpgradeTo.upgradeTo.selector, targetImpl);
    }

    function getUpgradeAndCallCalldata(address targetImpl, bytes memory call) internal pure returns (bytes memory upgradeCalldata) {
        upgradeCalldata = abi.encodeWithSelector(UUPSUpgradeableUpgradeTo.upgradeToAndCall.selector, targetImpl, call);
    }

    function simulateUpgrade(address targetProxy, address targetImpl) internal returns (bytes memory upgradeCalldata) {
        // console log update information

        upgradeCalldata = getUpgradeCalldata(targetImpl);

        // upgrade the factory proxy to the new implementation
        (bool success, ) = targetProxy.call(upgradeCalldata);

        require(success, "upgrade failed");
    }

    function performNeededUpgrades(address upgrader, UpgradeStatus[] memory upgradeStatuses) internal returns (bool anyUpgradePerformed) {
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

    function readMissingUpgradePaths() internal view returns (address[] memory upgradePathTargets, bytes[] memory upgradePathCalls) {
        string memory json = vm.readFile(string.concat("./versions/", string.concat(vm.toString(block.chainid), ".json")));

        upgradePathTargets = json.readAddressArray(".missingUpgradePathTargets");
        upgradePathCalls = json.readBytesArray(".missingUpgradePathCalls");
    }

    function getUpgradeNeeded(address proxy, address targetImpl) internal view returns (bool) {
        try GetImplementation(proxy).implementation() returns (address currentImpl) {
            return currentImpl != targetImpl;
        } catch {
            // If implementation() call fails, compare contract versions
            string memory proxyVersion = IVersionedContract(proxy).contractVersion();
            string memory targetVersion = IVersionedContract(targetImpl).contractVersion();
            return keccak256(abi.encodePacked(proxyVersion)) != keccak256(abi.encodePacked(targetVersion));
        }
    }
}
