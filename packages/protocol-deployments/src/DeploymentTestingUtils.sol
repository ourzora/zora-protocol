// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {IMinter1155} from "@zoralabs/zora-1155-contracts/src/interfaces/IMinter1155.sol";
import {ZoraCreator1155PremintExecutorImpl} from "@zoralabs/zora-1155-contracts/src/delegation/ZoraCreator1155PremintExecutorImpl.sol";
import {ZoraCreator1155FactoryImpl} from "@zoralabs/zora-1155-contracts/src/factory/ZoraCreator1155FactoryImpl.sol";
import {ZoraCreator1155Attribution, ContractCreationConfig, PremintConfig, TokenCreationConfig} from "@zoralabs/zora-1155-contracts/src/delegation/ZoraCreator1155Attribution.sol";
import {ZoraCreator1155Impl} from "@zoralabs/zora-1155-contracts/src/nft/ZoraCreator1155Impl.sol";

contract DeploymentTestingUtils is Script {
    function signAndExecutePremint(address premintExecutorProxyAddress) internal {
        console2.log("preminter proxy", premintExecutorProxyAddress);

        (address creator, uint256 creatorPrivateKey) = makeAddrAndKey("creator");
        ZoraCreator1155PremintExecutorImpl preminterAtProxy = ZoraCreator1155PremintExecutorImpl(premintExecutorProxyAddress);

        IMinter1155 fixedPriceMinter = ZoraCreator1155FactoryImpl(address(preminterAtProxy.zora1155Factory())).fixedPriceMinter();

        PremintConfig memory premintConfig = PremintConfig({
            tokenConfig: TokenCreationConfig({
                tokenURI: "blah.token",
                maxSupply: 10,
                maxTokensPerAddress: 5,
                pricePerToken: 0,
                mintStart: 0,
                mintDuration: 0,
                royaltyMintSchedule: 0,
                royaltyBPS: 100,
                royaltyRecipient: creator,
                fixedPriceMinter: address(fixedPriceMinter)
            }),
            uid: 100,
            version: 0,
            deleted: false
        });

        // now interface with proxy preminter - sign and execute the premint
        ContractCreationConfig memory contractConfig = ContractCreationConfig({contractAdmin: creator, contractName: "blah", contractURI: "blah.contract"});
        address deterministicAddress = preminterAtProxy.getContractAddress(contractConfig);

        // sign the premint
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(premintConfig, deterministicAddress, block.chainid);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(creatorPrivateKey, digest);

        uint256 quantityToMint = 1;

        bytes memory signature = abi.encodePacked(r, s, v);

        // execute the premint
        uint256 tokenId = preminterAtProxy.premint{value: 0.000777 ether}(contractConfig, premintConfig, signature, quantityToMint, "");

        require(ZoraCreator1155Impl(deterministicAddress).delegatedTokenId(premintConfig.uid) == tokenId, "token id not created for uid");
    }
}
