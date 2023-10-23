// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {IMinter1155} from "..//interfaces/IMinter1155.sol";
import {Zora1155FactoryFixtures} from "../../test/fixtures/Zora1155FactoryFixtures.sol";
import {Zora1155PremintFixtures} from "../../test/fixtures/Zora1155PremintFixtures.sol";
import {ZoraCreator1155PremintExecutorImpl} from "../delegation/ZoraCreator1155PremintExecutorImpl.sol";
import {IZoraCreator1155PremintExecutor} from "../interfaces/IZoraCreator1155PremintExecutor.sol";
import {ZoraCreator1155FactoryImpl} from "../factory/ZoraCreator1155FactoryImpl.sol";
import {ZoraCreator1155Attribution, ContractCreationConfig, PremintConfigV2} from "../delegation/ZoraCreator1155Attribution.sol";
import {ZoraCreator1155Impl} from "../nft/ZoraCreator1155Impl.sol";
import {ZoraCreator1155PremintExecutorImplLib} from "../delegation/ZoraCreator1155PremintExecutorImplLib.sol";

contract DeploymentTestingUtils is Script {
    function signAndExecutePremint(address premintExecutorProxyAddress, address fundsRecipient) internal {
        console2.log("preminter proxy", premintExecutorProxyAddress);

        (address creator, uint256 creatorPrivateKey) = makeAddrAndKey("creator");
        IZoraCreator1155PremintExecutor preminterAtProxy = IZoraCreator1155PremintExecutor(premintExecutorProxyAddress);

        IMinter1155 fixedPriceMinter = ZoraCreator1155FactoryImpl(address(preminterAtProxy.zora1155Factory())).fixedPriceMinter();

        PremintConfigV2 memory premintConfig = PremintConfigV2({
            tokenConfig: Zora1155PremintFixtures.makeDefaultTokenCreationConfigV2(fixedPriceMinter, fundsRecipient),
            uid: 100,
            version: 0,
            deleted: false
        });

        // now interface with proxy preminter - sign and execute the premint
        ContractCreationConfig memory contractConfig = Zora1155PremintFixtures.makeDefaultContractCreationConfig(creator);
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
