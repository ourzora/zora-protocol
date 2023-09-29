// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {IZoraCreator1155Errors} from "../../src/interfaces/IZoraCreator1155Errors.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {Zora1155Factory} from "../../src/proxies/Zora1155Factory.sol";
import {ZoraCreator1155FactoryImpl} from "../../src/factory/ZoraCreator1155FactoryImpl.sol";
import {ProtocolRewards} from "@zoralabs/protocol-rewards/src/ProtocolRewards.sol";
import {ProxyShim} from "../../src/utils/ProxyShim.sol";
import {ContractCreationConfig, TokenCreationConfig, PremintConfig} from "../../src/delegation/ZoraCreator1155Attribution.sol";

library Zora1155PremintFixtures {
    function makeDefaultContractCreationConfig(address contractAdmin) internal pure returns (ContractCreationConfig memory) {
        return ContractCreationConfig({contractAdmin: contractAdmin, contractName: "blah", contractURI: "blah.contract"});
    }

    function defaultRoyaltyConfig(address royaltyRecipient) internal pure returns (ICreatorRoyaltiesControl.RoyaltyConfiguration memory) {
        return ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyBPS: 10, royaltyRecipient: royaltyRecipient, royaltyMintSchedule: 100});
    }

    function makeDefaultTokenCreationConfig(IMinter1155 fixedPriceMinter, address royaltyRecipient) internal pure returns (TokenCreationConfig memory) {
        ICreatorRoyaltiesControl.RoyaltyConfiguration memory royaltyConfig = defaultRoyaltyConfig(royaltyRecipient);
        return
            TokenCreationConfig({
                tokenURI: "blah.token",
                maxSupply: 10,
                maxTokensPerAddress: 5,
                pricePerToken: 0,
                mintStart: 0,
                mintDuration: 0,
                royaltyMintSchedule: royaltyConfig.royaltyMintSchedule,
                royaltyBPS: royaltyConfig.royaltyBPS,
                royaltyRecipient: royaltyConfig.royaltyRecipient,
                fixedPriceMinter: address(fixedPriceMinter)
            });
    }
}
