// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {IZoraCreator1155Errors} from "../../src/interfaces/IZoraCreator1155Errors.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {Zora1155Factory} from "../../src/proxies/Zora1155Factory.sol";
import {ZoraCreator1155FactoryImpl} from "../../src/factory/ZoraCreator1155FactoryImpl.sol";
import {ProtocolRewards} from "@zoralabs/protocol-rewards/src/ProtocolRewards.sol";
import {ProxyShim} from "../../src/utils/ProxyShim.sol";
import {PremintConfig, ContractCreationConfig, TokenCreationConfigV2, TokenCreationConfig} from "../../src/delegation/ZoraCreator1155Attribution.sol";

library Zora1155PremintFixtures {
    function makeDefaultContractCreationConfig(address contractAdmin) internal pure returns (ContractCreationConfig memory) {
        return ContractCreationConfig({contractAdmin: contractAdmin, contractName: "blah", contractURI: "blah.contract"});
    }

    function makeDefaultTokenCreationConfigV2(IMinter1155 fixedPriceMinter, address royaltyRecipient) internal pure returns (TokenCreationConfigV2 memory) {
        return
            TokenCreationConfigV2({
                tokenURI: "blah.token",
                maxSupply: 18446744073709551615,
                maxTokensPerAddress: 0,
                pricePerToken: 0,
                mintStart: 0,
                mintDuration: 0,
                fixedPriceMinter: address(fixedPriceMinter),
                payoutRecipient: royaltyRecipient,
                royaltyBPS: 0,
                createReferral: address(0)
            });
    }

    function makeTokenCreationConfigV2WithCreateReferral(
        IMinter1155 fixedPriceMinter,
        address createReferral,
        address royaltyRecipient
    ) internal pure returns (TokenCreationConfigV2 memory) {
        return
            TokenCreationConfigV2({
                tokenURI: "blah.token",
                maxSupply: 18446744073709551615,
                maxTokensPerAddress: 0,
                pricePerToken: 0,
                mintStart: 0,
                mintDuration: 0,
                fixedPriceMinter: address(fixedPriceMinter),
                payoutRecipient: royaltyRecipient,
                royaltyBPS: 10,
                createReferral: createReferral
            });
    }

    function makeDefaultV1PremintConfig(IMinter1155 fixedPriceMinter, address royaltyRecipient) internal pure returns (PremintConfig memory) {
        // make a v1 premint config
        return
            PremintConfig({
                tokenConfig: TokenCreationConfig({
                    tokenURI: "blah.token",
                    maxSupply: 10,
                    maxTokensPerAddress: 5,
                    pricePerToken: 0,
                    mintStart: 0,
                    mintDuration: 0,
                    fixedPriceMinter: address(fixedPriceMinter),
                    royaltyRecipient: royaltyRecipient,
                    royaltyBPS: 10,
                    royaltyMintSchedule: 0
                }),
                uid: 100,
                version: 0,
                deleted: false
            });
    }
}
