// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "./ZoraDeployerBase.sol";
import {ProtocolRewards} from "@zoralabs/protocol-rewards/src/ProtocolRewards.sol";
import {ChainConfig, Deployment} from "../src/deployment/DeploymentConfig.sol";

import {ZoraCreator1155FactoryImpl} from "../src/factory/ZoraCreator1155FactoryImpl.sol";
import {Zora1155Factory} from "../src/proxies/Zora1155Factory.sol";
import {ZoraCreator1155Impl} from "../src/nft/ZoraCreator1155Impl.sol";
import {ICreatorRoyaltiesControl} from "../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../src/interfaces/IZoraCreator1155Factory.sol";
import {IMinter1155} from "../src/interfaces/IMinter1155.sol";
import {IZoraCreator1155} from "../src/interfaces/IZoraCreator1155.sol";
import {ProxyShim} from "../src/utils/ProxyShim.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {ZoraCreatorMerkleMinterStrategy} from "../src/minters/merkle/ZoraCreatorMerkleMinterStrategy.sol";
import {ZoraCreatorRedeemMinterFactory} from "../src/minters/redeem/ZoraCreatorRedeemMinterFactory.sol";

contract DeployScript is ZoraDeployerBase {
    function run() public {
        // ChainConfig memory chainConfig = getChainConfig();

        // console2.log("zoraFeeRecipient", chainConfig.mintFeeRecipient);
        // console2.log("factoryOwner", chainConfig.factoryOwner);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        ICreatorRoyaltiesControl.RoyaltyConfiguration memory royaltyConfig = ICreatorRoyaltiesControl.RoyaltyConfiguration({
            royaltyBPS: 10,
            royaltyRecipient: vm.addr(5),
            royaltyMintSchedule: 100
        });
        bytes[] memory initSetup = new bytes[](1);
        initSetup[0] = abi.encodeWithSelector(IZoraCreator1155.setupNewToken.selector, "ipfs://asdfadsf", 100);
        string memory uri = "ipfs://asdfadsf";
        string memory nameA = "nameA";

        vm.startBroadcast(deployerPrivateKey);

        ZoraCreator1155Impl zoraCreator1155Impl = new ZoraCreator1155Impl(address(0), address(0), address(new ProtocolRewards()));
        // get above constructor args encoded for verification later:
        ZoraCreator1155FactoryImpl factory = new ZoraCreator1155FactoryImpl(
            zoraCreator1155Impl,
            IMinter1155(address(1)),
            IMinter1155(address(2)),
            IMinter1155(address(3))
        );

        address factoryOwner = deployer;

        // 1. create the proxy, pointing it to the factory implentation and setting the owner
        ZoraCreator1155FactoryImpl proxy = ZoraCreator1155FactoryImpl(
            payable(new Zora1155Factory(address(factory), abi.encodeWithSelector(ZoraCreator1155FactoryImpl.initialize.selector, factoryOwner)))
        );

        address createdErc1155 = proxy.createContractDeterministic(uri, nameA, royaltyConfig, payable(deployer), initSetup);

        console.log("deployed erc1155 at", createdErc1155);
        console.log("constructor args", string(abi.encode(0, address(0), address(0))));
        vm.stopBroadcast();
    }
}
