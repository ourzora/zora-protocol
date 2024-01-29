// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ZoraCreator1155Impl} from "@zoralabs/zora-1155-contracts/src/nft/ZoraCreator1155Impl.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "@zoralabs/zora-1155-contracts/src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {IZoraCreator1155Errors} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155Errors.sol";
import {IMinter1155} from "@zoralabs/zora-1155-contracts/src/interfaces/IMinter1155.sol";
import {Zora1155Factory} from "@zoralabs/zora-1155-contracts/src/proxies/Zora1155Factory.sol";
import {ZoraCreator1155FactoryImpl} from "@zoralabs/zora-1155-contracts/src/factory/ZoraCreator1155FactoryImpl.sol";
import {ProtocolRewards} from "@zoralabs/protocol-rewards/src/ProtocolRewards.sol";
import {ProxyShim} from "@zoralabs/zora-1155-contracts/src/utils/ProxyShim.sol";
import {PremintConfig, PremintConfigV2, ContractCreationConfig, TokenCreationConfigV2, TokenCreationConfig} from "@zoralabs/zora-1155-contracts/src/delegation/ZoraCreator1155Attribution.sol";

library Zora1155PremintFixtures {
    function makeDefaultContractCreationConfig(address contractAdmin) internal pure returns (ContractCreationConfig memory) {
        return ContractCreationConfig({contractAdmin: contractAdmin, contractName: "blah_______blah", contractURI: "blah.contract"});
    }

    function makeTokenCreationConfigV2WithCreateReferral(
        IMinter1155 fixedPriceMinter,
        address payoutRecipient,
        address createReferral
    ) internal pure returns (TokenCreationConfigV2 memory) {
        return
            TokenCreationConfigV2({
                tokenURI: "blah.token",
                maxSupply: 10,
                maxTokensPerAddress: 5,
                pricePerToken: 0,
                mintStart: 0,
                mintDuration: 0,
                fixedPriceMinter: address(fixedPriceMinter),
                payoutRecipient: payoutRecipient,
                royaltyBPS: 10,
                createReferral: createReferral
            });
    }

    function makeDefaultV2PremintConfig(
        IMinter1155 fixedPriceMinter,
        address payoutRecipient,
        address createReferral
    ) internal pure returns (PremintConfigV2 memory) {
        // make a v2 premint config
        return
            PremintConfigV2({
                tokenConfig: makeTokenCreationConfigV2WithCreateReferral(fixedPriceMinter, payoutRecipient, createReferral),
                uid: 100,
                version: 0,
                deleted: false
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
