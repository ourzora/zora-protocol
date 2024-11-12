// spdx-license-identifier: MIT
pragma solidity ^0.8.17;

import {CommonBase} from "forge-std/Base.sol";

contract ForkDeploymentConfig is CommonBase {
    function chainId() internal view returns (uint256 id) {
        return block.chainid;
    }

    /// @notice gets the chains to do fork tests on, by reading environment var FORK_TEST_CHAINS.
    /// Chains are by name, and must match whats under `rpc_endpoints` in the foundry.toml
    function getForkTestChains() internal view returns (string[] memory result) {
        try vm.envString("FORK_TEST_CHAINS", ",") returns (string[] memory forkTestChains) {
            result = forkTestChains;
        } catch {
            result = new string[](0);
        }
    }

    // check if FORK_TEST_CHAINS is set in the environment, if it is, checks if the chainName is in the list
    // if it isn't indicates to skip testing on this fork.
    function shouldRunTestOnFork(string memory chainName) internal view returns (bool shouldRun) {
        string[] memory forkTestChains = getForkTestChains();

        // if there is no fork test chains, run all fork tests
        if (forkTestChains.length == 0) {
            return true;
        }

        bytes32 chainHash = keccak256(bytes(chainName));

        // if there are fork test chains in env, see if this fork test
        // chain is contained within; if it is, then run it
        for (uint256 i = 0; i < forkTestChains.length; i++) {
            if (keccak256(bytes(forkTestChains[i])) == chainHash) {
                return true;
            }
        }

        // if not found, return false;
        return false;
    }

    function setupForkTest(string memory chainName) internal {
        bool shouldRun = shouldRunTestOnFork(chainName);

        if (!shouldRun) {
            vm.skip(true);
            return;
        }

        vm.createSelectFork(chainName);
    }
}

contract ScriptDeploymentConfig {
    function chainId() internal view returns (uint256 id) {
        assembly {
            id := chainid()
        }
    }
}
