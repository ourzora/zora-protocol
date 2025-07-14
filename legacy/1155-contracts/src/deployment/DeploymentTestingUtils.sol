// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

import "forge-std/Script.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {IZoraCreator1155PremintExecutor} from "../interfaces/IZoraCreator1155PremintExecutor.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreator1155FactoryImpl} from "../factory/ZoraCreator1155FactoryImpl.sol";
import {ZoraCreator1155Attribution} from "../delegation/ZoraCreator1155Attribution.sol";
import {ContractCreationConfig, PremintConfigV2, TokenCreationConfigV2, PremintConfig, TokenCreationConfig, MintArguments, PremintResult} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {PremintEncoding} from "@zoralabs/shared-contracts/premint/PremintEncoding.sol";
import {ZoraCreator1155Impl} from "../nft/ZoraCreator1155Impl.sol";

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

    function signAndExecutePremintV1(address premintExecutorProxyAddress, address payoutRecipient, MintArguments memory mintArguments) internal {
        (
            ContractCreationConfig memory contractConfig,
            IZoraCreator1155PremintExecutor preminterAtProxy,
            PremintConfig memory premintConfig,
            bytes memory signature
        ) = createAndSignPremintV1(premintExecutorProxyAddress, payoutRecipient);

        uint256 quantityToMint = 1;

        address contractAddress = preminterAtProxy.getContractAddress(contractConfig);

        uint256 mintFee = preminterAtProxy.mintFee(contractAddress) * quantityToMint;

        // execute the premint
        PremintResult memory premintResult = preminterAtProxy.premintV1{value: mintFee}(
            contractConfig,
            premintConfig,
            signature,
            quantityToMint,
            mintArguments
        );

        require(ZoraCreator1155Impl(payable(contractAddress)).delegatedTokenId(premintConfig.uid) == premintResult.tokenId, "token id mismatch");
    }

    function createAndSignPremintV2(
        address premintExecutorProxyAddress,
        address payoutRecipient,
        uint32 uid
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
                tokenURI: "token.uri",
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
            uid: uid,
            version: 0,
            deleted: false
        });

        // now interface with proxy preminter - sign and execute the premint
        contractConfig = ContractCreationConfig({contractAdmin: creator, contractName: "blahb", contractURI: "blah.contractssss"});
        address deterministicAddress = preminterAtProxy.getContractAddress(contractConfig);

        signature = signPremint(premintConfig, deterministicAddress, creatorPrivateKey);
    }

    function signAndExecutePremintV2(address premintExecutorProxyAddress, address payoutRecipient, MintArguments memory mintArguments) internal {
        (
            ContractCreationConfig memory contractConfig,
            IZoraCreator1155PremintExecutor preminterAtProxy,
            PremintConfigV2 memory premintConfig,
            bytes memory signature
        ) = createAndSignPremintV2(premintExecutorProxyAddress, payoutRecipient, 100);

        uint256 quantityToMint = 1;
        address contractAddress = preminterAtProxy.getContractAddress(contractConfig);
        uint256 mintFee = preminterAtProxy.mintFee(contractAddress) * quantityToMint;
        // execute the premint
        uint256 tokenId = preminterAtProxy.premintV2{value: mintFee}(contractConfig, premintConfig, signature, quantityToMint, mintArguments).tokenId;

        require(ZoraCreator1155Impl(payable(contractAddress)).delegatedTokenId(premintConfig.uid) == tokenId, "token id not created for uid");
    }

    function signPremint(PremintConfigV2 memory premintConfig, address deterministicAddress, uint256 privateKey) private view returns (bytes memory signature) {
        bytes32 signatureVersion = PremintEncoding.HASHED_VERSION_2;
        bytes32 structHash = ZoraCreator1155Attribution.hashPremint(premintConfig);
        // sign the premint
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(structHash, deterministicAddress, signatureVersion, block.chainid);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function signPremint(PremintConfig memory premintConfig, address deterministicAddress, uint256 privateKey) private view returns (bytes memory signature) {
        bytes32 signatureVersion = PremintEncoding.HASHED_VERSION_1;
        bytes32 structHash = ZoraCreator1155Attribution.hashPremint(premintConfig);
        // sign the premint
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(structHash, deterministicAddress, signatureVersion, block.chainid);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
