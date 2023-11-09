// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {ForkDeploymentConfig, Deployment, ChainConfig} from "../src/DeploymentConfig.sol";
import {ZoraDeployerUtils} from "../src/ZoraDeployerUtils.sol";

import {Zora1155Factory} from "@zoralabs/zora-1155-contracts/src/proxies/Zora1155Factory.sol";
import {ZoraCreator1155FactoryImpl} from "@zoralabs/zora-1155-contracts/src/factory/ZoraCreator1155FactoryImpl.sol";
import {ZoraCreator1155Impl} from "@zoralabs/zora-1155-contracts/src/nft/ZoraCreator1155Impl.sol";
import {ICreatorRoyaltiesControl} from "@zoralabs/zora-1155-contracts/src/interfaces/ICreatorRoyaltiesControl.sol";
import {IMinter1155} from "@zoralabs/zora-1155-contracts/src/interfaces/IMinter1155.sol";

contract ZoraCreator1155SupplyRoyaltyDeprecationTest is Test, ForkDeploymentConfig {
    address internal creator;
    string[] internal chains;

    function setUp() public {
        creator = makeAddr("creator");

        chains = new string[](1);
        chains[0] = "zora_goerli";
    }

    function testFork_SupplyRoyaltyDeprecation() public {
        for (uint256 i; i < chains.length; ++i) {
            string memory chain = chains[i];

            vm.createSelectFork(vm.rpcUrl(chain));

            Deployment memory deployment = getDeployment();
            ChainConfig memory chainConfig = getChainConfig();

            ZoraCreator1155FactoryImpl factory = ZoraCreator1155FactoryImpl(deployment.factoryProxy);

            uint32 invalidRoyaltyMintSchedule = 10;

            ICreatorRoyaltiesControl.RoyaltyConfiguration memory royaltyConfig = ICreatorRoyaltiesControl.RoyaltyConfiguration({
                royaltyBPS: 0,
                royaltyRecipient: address(0),
                royaltyMintSchedule: invalidRoyaltyMintSchedule
            });

            vm.expectRevert(abi.encodeWithSignature("InvalidMintSchedule()"));
            factory.createContract("mock uri", "mock name", royaltyConfig, payable(creator), new bytes[](0));

            (address newFactoryImpl, , ) = ZoraDeployerUtils.deployNew1155AndFactoryImpl({
                upgradeGateAddress: deployment.upgradeGate,
                mintFeeRecipient: chainConfig.mintFeeRecipient,
                protocolRewards: chainConfig.protocolRewards,
                merkleMinter: IMinter1155(deployment.merkleMintSaleStrategy),
                redeemMinterFactory: IMinter1155(deployment.redeemMinterFactory),
                fixedPriceMinter: IMinter1155(deployment.fixedPriceSaleStrategy)
            });

            ZoraCreator1155FactoryImpl newFactory = ZoraCreator1155FactoryImpl(address(new Zora1155Factory(newFactoryImpl, "")));

            address tokenContractAddress = newFactory.createContract("mock uri", "mock name", royaltyConfig, payable(creator), new bytes[](0));

            ZoraCreator1155Impl tokenContract = ZoraCreator1155Impl(tokenContractAddress);

            // Ensure the specified royalty mint schedule is ignored + set to zero
            assertEq(tokenContract.getRoyalties(0).royaltyMintSchedule, 0);
        }
    }
}
