// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ForkDeploymentConfig} from "../src/DeploymentConfig.sol";
import {PremintEncoding} from "@zoralabs/shared-contracts/premint/PremintEncoding.sol";
import {ZoraCreator1155Attribution} from "@zoralabs/zora-1155-contracts/src/delegation/ZoraCreator1155Attribution.sol";
import {ContractCreationConfig, PremintConfig, PremintConfigV2, TokenCreationConfig, MintArguments} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {ZoraCreator1155PremintExecutorImpl} from "@zoralabs/zora-1155-contracts/src/delegation/ZoraCreator1155PremintExecutorImpl.sol";
import {ZoraCreator1155FactoryImpl} from "@zoralabs/zora-1155-contracts/src/factory/ZoraCreator1155FactoryImpl.sol";
import {IZoraCreator1155PremintExecutor} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155PremintExecutor.sol";
import {Zora1155PremintFixtures} from "../src/Zora1155PremintFixtures.sol";

contract ZoraCreator1155PremintExecutorBase is ForkDeploymentConfig, Test {
    ZoraCreator1155FactoryImpl factory;
    ZoraCreator1155PremintExecutorImpl preminter;
    address creator;
    uint256 creatorPrivateKey;
    address payoutRecipient = makeAddr("payoutRecipient");
    address minter = makeAddr("minter");

    ContractCreationConfig contractConfig;
    PremintConfig premintConfig;
    PremintConfigV2 premintConfigV2;
    address createReferral = makeAddr("creatReferral");

    function setupPremint() private {
        // get contract hash, which is unique per contract creation config, and can be used
        // retrieve the address created for a contract
        address preminterAddress = getDeployment().preminterProxy;

        // override local preminter to use the addresses from the chain
        factory = ZoraCreator1155FactoryImpl(getDeployment().factoryProxy);
        preminter = ZoraCreator1155PremintExecutorImpl(preminterAddress);

        (creator, creatorPrivateKey) = makeAddrAndKey("creator");

        contractConfig = Zora1155PremintFixtures.makeDefaultContractCreationConfig(creator);

        premintConfig = Zora1155PremintFixtures.makeDefaultV1PremintConfig(factory.fixedPriceMinter(), payoutRecipient);
        premintConfigV2 = Zora1155PremintFixtures.makeDefaultV2PremintConfig(factory.fixedPriceMinter(), payoutRecipient, createReferral);
    }

    function legacyPremint_successfullyMintsPremintTokens() internal {
        setupPremint();

        _signAndExecutePremintLegacy(creatorPrivateKey, minter, 1, "test comment");
    }

    function premintV1_successfullyMintsPremintTokens() internal {
        setupPremint();

        _signAndExecutePremintV1(creatorPrivateKey, minter, 1, "test comment");
    }

    function premintV2_successfullyMintsPremintTokens() internal {
        setupPremint();

        _signAndExecutePremintV2(creatorPrivateKey, minter, 0, "test comment");
    }

    function _signAndExecutePremintLegacy(
        uint256 privateKey,
        address executor,
        uint256 quantityToMint,
        string memory comment
    ) private returns (uint256 newTokenId) {
        address contractAddress = preminter.getContractAddress(contractConfig);
        bytes memory signature = _signPremintV1(contractAddress, privateKey, block.chainid);

        uint256 mintCost = preminter.mintFee(contractAddress) * quantityToMint;
        vm.deal(executor, mintCost);

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.prank(executor);
        MintArguments memory mintArguments;
        mintArguments.mintComment = comment;
        mintArguments.mintRecipient = executor;
        newTokenId = preminter.premintV1{value: mintCost}(contractConfig, premintConfig, signature, quantityToMint, mintArguments).tokenId;
    }

    function _signAndExecutePremintV1(uint256 privateKey, address executor, uint256 quantityToMint, string memory comment) private {
        address contractAddress = preminter.getContractAddress(contractConfig);
        bytes memory signature = _signPremintV1(contractAddress, privateKey, block.chainid);

        uint256 mintCost = preminter.mintFee(contractAddress) * quantityToMint;
        vm.deal(executor, mintCost);

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.prank(executor);
        preminter.premintV1{value: mintCost}(
            contractConfig,
            premintConfig,
            signature,
            quantityToMint,
            MintArguments({mintRecipient: executor, mintComment: comment, mintRewardsRecipients: new address[](0)})
        );
    }

    function _signPremintV1(address contractAddress, uint256 privateKey, uint256 chainId) private view returns (bytes memory) {
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(
            ZoraCreator1155Attribution.hashPremint(premintConfig),
            contractAddress,
            PremintEncoding.HASHED_VERSION_1,
            chainId
        );

        // 3. Sign the digest
        // create a signature with the digest for the params
        return _sign(privateKey, digest);
    }

    function _signAndExecutePremintV2(uint256 privateKey, address executor, uint256 quantityToMint, string memory comment) private {
        address contractAddress = preminter.getContractAddress(contractConfig);
        bytes memory signature = _signPremintV2(contractAddress, privateKey, block.chainid);

        uint256 mintCost = preminter.mintFee(contractAddress) * quantityToMint;
        vm.deal(executor, mintCost);

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.prank(executor);
        preminter.premintV2{value: mintCost}(
            contractConfig,
            premintConfigV2,
            signature,
            quantityToMint,
            MintArguments({mintRecipient: executor, mintComment: comment, mintRewardsRecipients: new address[](0)})
        );
    }

    function _signPremintV2(address contractAddress, uint256 privateKey, uint256 chainId) private view returns (bytes memory) {
        bytes32 digest = ZoraCreator1155Attribution.premintHashedTypeDataV4(
            ZoraCreator1155Attribution.hashPremint(premintConfigV2),
            contractAddress,
            PremintEncoding.HASHED_VERSION_2,
            chainId
        );

        // 3. Sign the digest
        // create a signature with the digest for the params
        return _sign(privateKey, digest);
    }

    function _sign(uint256 privateKey, bytes32 digest) private pure returns (bytes memory) {
        // sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // combine into a single bytes array
        return abi.encodePacked(r, s, v);
    }
}
