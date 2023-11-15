// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {IMinter1155} from "@zoralabs/zora-1155-contracts/src/interfaces/IMinter1155.sol";
import {IZoraCreator1155PremintExecutor} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155PremintExecutor.sol";
import {ZoraCreator1155PremintExecutorImpl} from "@zoralabs/zora-1155-contracts/src/delegation/ZoraCreator1155PremintExecutorImpl.sol";
import {ZoraCreator1155FactoryImpl} from "@zoralabs/zora-1155-contracts/src/factory/ZoraCreator1155FactoryImpl.sol";
import {ZoraCreator1155Attribution, ContractCreationConfig, PremintConfigV2, TokenCreationConfigV2} from "@zoralabs/zora-1155-contracts/src/delegation/ZoraCreator1155Attribution.sol";
import {ZoraCreator1155Impl} from "@zoralabs/zora-1155-contracts/src/nft/ZoraCreator1155Impl.sol";

contract DeploymentTestingUtils is Script {
    function signAndExecutePremint(address premintExecutorProxyAddress, address payoutRecipient) internal {
        console2.log("preminter proxy", premintExecutorProxyAddress);

        (address creator, uint256 creatorPrivateKey) = makeAddrAndKey("creator");
        IZoraCreator1155PremintExecutor preminterAtProxy = IZoraCreator1155PremintExecutor(premintExecutorProxyAddress);

        IMinter1155 fixedPriceMinter = ZoraCreator1155FactoryImpl(address(preminterAtProxy.zora1155Factory())).fixedPriceMinter();

        PremintConfigV2 memory premintConfig = PremintConfigV2({
            tokenConfig: TokenCreationConfigV2({
                tokenURI: "blah.token",
                maxSupply: 10,
                maxTokensPerAddress: 5,
                pricePerToken: 0,
                mintStart: 0,
                mintDuration: 0,
                royaltyBPS: 100,
                payoutRecipient: payoutRecipient,
                fixedPriceMinter: address(fixedPriceMinter),
                createReferral: address(0)
            }),
            uid: 100,
            version: 0,
            deleted: false
        });

        // now interface with proxy preminter - sign and execute the premint
        ContractCreationConfig memory contractConfig = ContractCreationConfig({contractAdmin: creator, contractName: "blah", contractURI: "blah.contract"});
        address deterministicAddress = preminterAtProxy.getContractAddress(contractConfig);

        uint256 quantityToMint = 1;

        address mintRecipient = creator;

        IZoraCreator1155PremintExecutor.MintArguments memory mintArguments = IZoraCreator1155PremintExecutor.MintArguments({
            mintRecipient: mintRecipient,
            mintComment: "",
            mintReferral: address(0)
        });

        bytes memory signature = signPremint(premintConfig, deterministicAddress, creatorPrivateKey);

        // execute the premint
        uint256 tokenId = preminterAtProxy.premintV2{value: 0.000777 ether}(contractConfig, premintConfig, signature, quantityToMint, mintArguments).tokenId;

        require(ZoraCreator1155Impl(deterministicAddress).delegatedTokenId(premintConfig.uid) == tokenId, "token id not created for uid");
    }

    function signPremint(PremintConfigV2 memory premintConfig, address deterministicAddress, uint256 privateKey) private view returns (bytes memory signature) {
        bytes32 signatureVersion = ZoraCreator1155Attribution.HASHED_VERSION_2;
        bytes32 structHash = ZoraCreator1155Attribution.hashPremint(premintConfig);
        // sign the premint
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(structHash, deterministicAddress, signatureVersion, block.chainid);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
