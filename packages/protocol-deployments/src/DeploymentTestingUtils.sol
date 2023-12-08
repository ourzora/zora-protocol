// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {IMinter1155} from "@zoralabs/zora-1155-contracts/src/interfaces/IMinter1155.sol";
import {IZoraCreator1155PremintExecutor} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155PremintExecutor.sol";
import {ZoraCreator1155PremintExecutorImpl} from "@zoralabs/zora-1155-contracts/src/delegation/ZoraCreator1155PremintExecutorImpl.sol";
import {ZoraCreator1155FactoryImpl} from "@zoralabs/zora-1155-contracts/src/factory/ZoraCreator1155FactoryImpl.sol";
import {ZoraCreator1155Attribution, ContractCreationConfig, PremintConfigV2, TokenCreationConfigV2, PremintConfig, TokenCreationConfig} from "@zoralabs/zora-1155-contracts/src/delegation/ZoraCreator1155Attribution.sol";
import {ScriptDeploymentConfig} from "./DeploymentConfig.sol";
import {ZoraCreator1155Impl} from "@zoralabs/zora-1155-contracts/src/nft/ZoraCreator1155Impl.sol";

contract DeploymentTestingUtils is Script {
    function createAndSignPremintV1(
        address premintExecutorProxyAddress,
        address payoutRecipient
    )
        internal
        returns (
            ContractCreationConfig memory contractConfig,
            IZoraCreator1155PremintExecutor preminterAtProxy,
            PremintConfig memory premintConfig,
            bytes memory signature
        )
    {
        (address creator, uint256 creatorPrivateKey) = makeAddrAndKey("creator");
        preminterAtProxy = IZoraCreator1155PremintExecutor(premintExecutorProxyAddress);

        premintConfig = PremintConfig({
            tokenConfig: TokenCreationConfig({
                tokenURI: "blah.token",
                maxSupply: 10,
                maxTokensPerAddress: 5,
                pricePerToken: 0,
                mintStart: 0,
                mintDuration: 0,
                royaltyMintSchedule: 0,
                royaltyBPS: 100,
                royaltyRecipient: payoutRecipient,
                fixedPriceMinter: address(ZoraCreator1155FactoryImpl(address(preminterAtProxy.zora1155Factory())).fixedPriceMinter())
            }),
            uid: 101,
            version: 0,
            deleted: false
        });

        // now interface with proxy preminter - sign and execute the premint
        contractConfig = ContractCreationConfig({contractAdmin: creator, contractName: "blahb", contractURI: "blah.contract"});
        address deterministicAddress = preminterAtProxy.getContractAddress(contractConfig);

        signature = signPremint(premintConfig, deterministicAddress, creatorPrivateKey);
    }

    function signAndExecutePremintV1(
        address premintExecutorProxyAddress,
        address payoutRecipient,
        IZoraCreator1155PremintExecutor.MintArguments memory mintArguments
    ) internal {
        (
            ContractCreationConfig memory contractConfig,
            IZoraCreator1155PremintExecutor preminterAtProxy,
            PremintConfig memory premintConfig,
            bytes memory signature
        ) = createAndSignPremintV1(premintExecutorProxyAddress, payoutRecipient);

        uint256 quantityToMint = 1;

        // execute the premint
        IZoraCreator1155PremintExecutor.PremintResult memory premintResult = preminterAtProxy.premintV1{value: mintFee(quantityToMint)}(
            contractConfig,
            premintConfig,
            signature,
            quantityToMint,
            mintArguments
        );

        require(ZoraCreator1155Impl(payable(premintResult.contractAddress)).delegatedTokenId(premintConfig.uid) == premintResult.tokenId, "token id mismatch");
    }

    function createAndSignPremintV2(
        address premintExecutorProxyAddress,
        address payoutRecipient
    )
        internal
        returns (
            ContractCreationConfig memory contractConfig,
            IZoraCreator1155PremintExecutor preminterAtProxy,
            PremintConfigV2 memory premintConfig,
            bytes memory signature
        )
    {
        (address creator, uint256 creatorPrivateKey) = makeAddrAndKey("creator");
        preminterAtProxy = IZoraCreator1155PremintExecutor(premintExecutorProxyAddress);

        premintConfig = PremintConfigV2({
            tokenConfig: TokenCreationConfigV2({
                tokenURI: "blah.token",
                maxSupply: 100,
                maxTokensPerAddress: 50,
                pricePerToken: 0,
                mintStart: 0,
                mintDuration: 0,
                royaltyBPS: 100,
                payoutRecipient: payoutRecipient,
                fixedPriceMinter: address(ZoraCreator1155FactoryImpl(address(preminterAtProxy.zora1155Factory())).fixedPriceMinter()),
                createReferral: creator
            }),
            uid: 100,
            version: 0,
            deleted: false
        });

        // now interface with proxy preminter - sign and execute the premint
        contractConfig = ContractCreationConfig({contractAdmin: creator, contractName: "blahb", contractURI: "blah.contract"});
        address deterministicAddress = preminterAtProxy.getContractAddress(contractConfig);

        signature = signPremint(premintConfig, deterministicAddress, creatorPrivateKey);
    }

    function signAndExecutePremintV2(
        address premintExecutorProxyAddress,
        address payoutRecipient,
        IZoraCreator1155PremintExecutor.MintArguments memory mintArguments
    ) internal {
        (
            ContractCreationConfig memory contractConfig,
            IZoraCreator1155PremintExecutor preminterAtProxy,
            PremintConfigV2 memory premintConfig,
            bytes memory signature
        ) = createAndSignPremintV2(premintExecutorProxyAddress, payoutRecipient);

        uint256 quantityToMint = 1;
        // execute the premint
        uint256 tokenId = preminterAtProxy
        .premintV2{value: mintFee(quantityToMint)}(contractConfig, premintConfig, signature, quantityToMint, mintArguments).tokenId;

        require(
            ZoraCreator1155Impl(payable(preminterAtProxy.getContractAddress(contractConfig))).delegatedTokenId(premintConfig.uid) == tokenId,
            "token id not created for uid"
        );
    }

    function signPremint(PremintConfigV2 memory premintConfig, address deterministicAddress, uint256 privateKey) private view returns (bytes memory signature) {
        bytes32 signatureVersion = ZoraCreator1155Attribution.HASHED_VERSION_2;
        bytes32 structHash = ZoraCreator1155Attribution.hashPremint(premintConfig);
        // sign the premint
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(structHash, deterministicAddress, signatureVersion, block.chainid);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function mintFee(uint256 quantityToMint) internal pure returns (uint256) {
        return quantityToMint * 0.000777 ether;
    }

    function signPremint(PremintConfig memory premintConfig, address deterministicAddress, uint256 privateKey) private view returns (bytes memory signature) {
        bytes32 signatureVersion = ZoraCreator1155Attribution.HASHED_VERSION_1;
        bytes32 structHash = ZoraCreator1155Attribution.hashPremint(premintConfig);
        // sign the premint
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(structHash, deterministicAddress, signatureVersion, block.chainid);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
