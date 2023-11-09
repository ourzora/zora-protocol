// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ForkDeploymentConfig} from "../src/DeploymentConfig.sol";
import {ZoraCreator1155Attribution, ContractCreationConfig, PremintConfig, TokenCreationConfig} from "@zoralabs/zora-1155-contracts/src/delegation/ZoraCreator1155Attribution.sol";
import {ZoraCreator1155PremintExecutorImpl} from "@zoralabs/zora-1155-contracts/src/delegation/ZoraCreator1155PremintExecutorImpl.sol";
import {ZoraCreator1155FactoryImpl} from "@zoralabs/zora-1155-contracts/src/factory/ZoraCreator1155FactoryImpl.sol";

contract ZoraCreator1155PreminterForkTest is ForkDeploymentConfig, Test {
    ZoraCreator1155FactoryImpl factory;
    ZoraCreator1155PremintExecutorImpl preminter;
    uint256 mintFeeAmount = 0.000777 ether;

    /// @notice gets the chains to do fork tests on, by reading environment var FORK_TEST_CHAINS.
    /// Chains are by name, and must match whats under `rpc_endpoints` in the foundry.toml
    function getForkTestChains() private view returns (string[] memory result) {
        try vm.envString("FORK_TEST_CHAINS", ",") returns (string[] memory forkTestChains) {
            result = forkTestChains;
        } catch {
            console.log("could not get fork test chains - make sure the environment variable FORK_TEST_CHAINS is set");
            result = new string[](0);
        }
    }

    function testTheForkPremint(string memory chainName) private {
        console.log("testing on fork: ", chainName);

        // create and select the fork, which will be used for all subsequent calls
        // it will also affect the current block chain id based on the rpc url returned
        vm.createSelectFork(vm.rpcUrl(chainName));

        // get contract hash, which is unique per contract creation config, and can be used
        // retreive the address created for a contract
        address preminterAddress = getDeployment().preminterProxy;

        if (preminterAddress == address(0)) {
            console.log("preminter not configured for chain...skipping");
            return;
        }

        // override local preminter to use the addresses from the chain
        factory = ZoraCreator1155FactoryImpl(getDeployment().factoryProxy);
        preminter = ZoraCreator1155PremintExecutorImpl(preminterAddress);
    }

    function test_fork_successfullyMintsTokens() external {
        string[] memory forkTestChains = getForkTestChains();
        for (uint256 i = 0; i < forkTestChains.length; i++) {
            testTheForkPremint(forkTestChains[i]);
        }
    }

    function _signAndExecutePremint(
        ContractCreationConfig memory contractConfig,
        PremintConfig memory premintConfig,
        uint256 privateKey,
        uint256 chainId,
        address executor,
        uint256 quantityToMint,
        string memory comment
    ) private returns (uint256 newTokenId) {
        bytes memory signature = _signPremint(preminter.getContractAddress(contractConfig), premintConfig, privateKey, chainId);

        uint256 mintCost = mintFeeAmount * quantityToMint;
        vm.deal(executor, mintCost);

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.prank(executor);
        newTokenId = preminter.premint{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, comment);
    }

    function _signPremint(
        address contractAddress,
        PremintConfig memory premintConfig,
        uint256 privateKey,
        uint256 chainId
    ) private pure returns (bytes memory) {
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(premintConfig, contractAddress, chainId);

        // 3. Sign the digest
        // create a signature with the digest for the params
        return _sign(privateKey, digest);
    }

    function _sign(uint256 privateKey, bytes32 digest) private pure returns (bytes memory) {
        // sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // combine into a single bytes array
        return abi.encodePacked(r, s, v);
    }
}
