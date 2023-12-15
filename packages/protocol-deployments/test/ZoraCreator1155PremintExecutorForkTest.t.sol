// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ForkDeploymentConfig} from "../src/DeploymentConfig.sol";
import {ZoraCreator1155Attribution, ContractCreationConfig, PremintConfig, PremintConfigV2, TokenCreationConfig} from "@zoralabs/zora-1155-contracts/src/delegation/ZoraCreator1155Attribution.sol";
import {ZoraCreator1155PremintExecutorImpl} from "@zoralabs/zora-1155-contracts/src/delegation/ZoraCreator1155PremintExecutorImpl.sol";
import {ZoraCreator1155FactoryImpl} from "@zoralabs/zora-1155-contracts/src/factory/ZoraCreator1155FactoryImpl.sol";
import {IZoraCreator1155PremintExecutor} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155PremintExecutor.sol";
import {Zora1155PremintFixtures} from "../src/Zora1155PremintFixtures.sol";

contract ZoraCreator1155PreminterForkTest is ForkDeploymentConfig, Test {
    ZoraCreator1155FactoryImpl factory;
    ZoraCreator1155PremintExecutorImpl preminter;
    uint256 mintFeeAmount = 0.000777 ether;
    address creator;
    uint256 creatorPrivateKey;
    address payoutRecipient = makeAddr("payoutRecipient");
    address minter = makeAddr("minter");

    ContractCreationConfig contractConfig;
    PremintConfig premintConfig;
    PremintConfigV2 premintConfigV2;
    address createReferral = makeAddr("creatReferral");

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

    function setupPremint() private {
        // get contract hash, which is unique per contract creation config, and can be used
        // retrieve the address created for a contract
        address preminterAddress = getDeployment().preminterProxy;

        // override local preminter to use the addresses from the chain
        factory = ZoraCreator1155FactoryImpl(getDeployment().factoryProxy);
        preminter = ZoraCreator1155PremintExecutorImpl(preminterAddress);

        (creator, creatorPrivateKey) = makeAddrAndKey("creator");

        contractConfig = Zora1155PremintFixtures.makeDefaultContractCreationConfig(creator);

        premintConfig = Zora1155PremintFixtures.makeDefaultV1PremintConfig(factory.fixedPriceMinter(), payoutRecipient);
        premintConfigV2 = Zora1155PremintFixtures.makeDefaultV2PremintConfig(factory.fixedPriceMinter(), payoutRecipient, createReferral);
    }

    function equals(string memory str1, string memory str2) public pure returns (bool) {
        return keccak256(abi.encodePacked(str1)) == keccak256(abi.encodePacked(str2));
    }

    function test_fork_legacyPremint_successfullyMintsPremintTokens() external {
        string[] memory forkTestChains = getForkTestChains();
        for (uint256 i = 0; i < forkTestChains.length; i++) {
            string memory chainName = forkTestChains[i];

            console.log("testing on fork: ", chainName);

            // create and select the fork, which will be used for all subsequent calls
            // it will also affect the current block chain id based on the rpc url returned
            vm.createSelectFork(vm.rpcUrl(chainName));

            setupPremint();

            _signAndExecutePremintLegacy(creatorPrivateKey, minter, 1, "test comment");
        }
    }

    function test_fork_premintV1_successfullyMintsPremintTokens() external {
        string[] memory forkTestChains = getForkTestChains();
        for (uint256 i = 0; i < forkTestChains.length; i++) {
            string memory chainName = forkTestChains[i];

            if (!_chainSupportsPremintV2(chainName)) {
                console.log("skipping chain, does not support v1 premint: ", chainName);
                continue;
            }

            console.log("testing on fork: ", chainName);

            // it will also affect the current block chain id based on the rpc url returned
            vm.createSelectFork(vm.rpcUrl(chainName));

            setupPremint();

            _signAndExecutePremintV1(creatorPrivateKey, minter, 1, "test comment");
        }
    }

    function test_fork_premintV2_successfullyMintsPremintTokens() external {
        string[] memory forkTestChains = getForkTestChains();
        for (uint256 i = 0; i < forkTestChains.length; i++) {
            string memory chainName = forkTestChains[i];

            if (!_chainSupportsPremintV2(chainName)) {
                console.log("skipping chain, does not support v2 premint: ", chainName);
                continue;
            }

            console.log("testing on fork: ", chainName);

            // it will also affect the current block chain id based on the rpc url returned
            vm.createSelectFork(vm.rpcUrl(chainName));

            setupPremint();

            _signAndExecutePremintV2(creatorPrivateKey, minter, 0, "test comment");
        }
    }

    function _chainSupportsPremintV2(string memory chainName) private pure returns (bool) {
        // for now we know that only goerli and sepolia have v2 premint deployed
        return (equals(chainName, "zora_sepolia") || equals(chainName, "zora_goerli"));
    }

    function _signAndExecutePremintLegacy(
        uint256 privateKey,
        address executor,
        uint256 quantityToMint,
        string memory comment
    ) private returns (uint256 newTokenId) {
        bytes memory signature = _signPremintV1(preminter.getContractAddress(contractConfig), privateKey, block.chainid);

        uint256 mintCost = mintFeeAmount * quantityToMint;
        vm.deal(executor, mintCost);

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.prank(executor);
        newTokenId = preminter.premint{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, comment);
    }

    function _signAndExecutePremintV1(uint256 privateKey, address executor, uint256 quantityToMint, string memory comment) private {
        bytes memory signature = _signPremintV1(preminter.getContractAddress(contractConfig), privateKey, block.chainid);

        uint256 mintCost = mintFeeAmount * quantityToMint;
        vm.deal(executor, mintCost);

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.prank(executor);
        preminter.premintV1{value: mintCost}(
            contractConfig,
            premintConfig,
            signature,
            quantityToMint,
            IZoraCreator1155PremintExecutor.MintArguments({mintRecipient: executor, mintComment: comment, mintRewardsRecipients: new address[](0)})
        );
    }

    function _signPremintV1(address contractAddress, uint256 privateKey, uint256 chainId) private view returns (bytes memory) {
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(
            ZoraCreator1155Attribution.hashPremint(premintConfig),
            contractAddress,
            ZoraCreator1155Attribution.HASHED_VERSION_1,
            chainId
        );

        // 3. Sign the digest
        // create a signature with the digest for the params
        return _sign(privateKey, digest);
    }

    function _signAndExecutePremintV2(uint256 privateKey, address executor, uint256 quantityToMint, string memory comment) private {
        bytes memory signature = _signPremintV2(preminter.getContractAddress(contractConfig), privateKey, block.chainid);

        uint256 mintCost = mintFeeAmount * quantityToMint;
        vm.deal(executor, mintCost);

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.prank(executor);
        preminter.premintV2{value: mintCost}(
            contractConfig,
            premintConfigV2,
            signature,
            quantityToMint,
            IZoraCreator1155PremintExecutor.MintArguments({mintRecipient: executor, mintComment: comment, mintRewardsRecipients: new address[](0)})
        );
    }

    function _signPremintV2(address contractAddress, uint256 privateKey, uint256 chainId) private view returns (bytes memory) {
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(
            ZoraCreator1155Attribution.hashPremint(premintConfigV2),
            contractAddress,
            ZoraCreator1155Attribution.HASHED_VERSION_2,
            chainId
        );

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
