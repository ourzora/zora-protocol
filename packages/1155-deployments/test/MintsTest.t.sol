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
import {IZoraMints1155Managed} from "@zoralabs/mints-contracts/src/interfaces/IZoraMints1155Managed.sol";
import {IZoraCreator1155} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155.sol";
import {IZoraCreator1155PremintExecutor} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155PremintExecutor.sol";
import {ContractCreationConfig, PremintConfigV2} from "@zoralabs/shared-contracts/entities/Premint.sol";

contract MintsTest is ForkDeploymentConfig, DeploymentTestingUtils, Test {
    using stdJson for string;

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

    function tryReadMintsImpl() private view returns (address mintsImpl) {
        string memory addressPath = string.concat("node_modules/@zoralabs/mints-deployments/addresses/", string.concat(vm.toString(block.chainid), ".json"));
        try vm.readFile(addressPath) returns (string memory result) {
            mintsImpl = result.readAddress(".MINTS_MANAGER_IMPL");
        } catch {}
    }

    function mintsIsDeployed() private view returns (bool) {
        return tryReadMintsImpl() != address(0);
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
        checkPremintWithMINTsWorks();
    }

    function test_fork_MINTs() external {
        string[] memory forkTestChains = getForkTestChains();
        for (uint256 i = 0; i < forkTestChains.length; i++) {
            vm.createSelectFork(vm.rpcUrl(forkTestChains[i]));
            checkContracts();
        }
    }
}
