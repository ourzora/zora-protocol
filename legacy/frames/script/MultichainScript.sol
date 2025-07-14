// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {BoostedMinterImpl} from "../src/BoostedMinterImpl.sol";
import {BoostedMinterFactoryImpl} from "../src/BoostedMinterFactoryImpl.sol";
import {BoostedMinterFactory} from "../src/BoostedMinterFactory.sol";

abstract contract MultichainScript is Script {
    function chainConfig() public view returns (string memory) {
        return vm.readFile(string.concat("./chainConfig/", vm.toString(getChainId()), ".json"));
    }

    function addresses() public view returns (string memory) {
        return vm.readFile(string.concat("./addresses/", vm.toString(getChainId()), ".json"));
    }

    function getChains() public view returns (string[] memory result) {
        return vm.envString("RUN_CHAINS", ",");
    }

    function getChainId() internal view returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }

    function runForChain() public virtual;

    function run() public {
        string[] memory chains = getChains();
        for (uint256 i = 0; i < chains.length; i++) {
            string memory chainName = chains[i];
            vm.createSelectFork(vm.rpcUrl(chainName));

            vm.startBroadcast(vm.envAddress("SENDER"));
            runForChain();
            vm.stopBroadcast();
        }
    }
}
