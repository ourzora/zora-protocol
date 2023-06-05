// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ECDSAUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";

import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155} from "../../src/proxies/Zora1155.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../../src/interfaces/IZoraCreator1155Factory.sol";
import {ILimitedMintPerAddress} from "../../src/interfaces/ILimitedMintPerAddress.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {Zora1155Factory} from "../../src/proxies/Zora1155Factory.sol";
import {ZoraCreator1155FactoryImpl} from "../../src/factory/ZoraCreator1155FactoryImpl.sol";
import {ZoraCreator1155Preminter} from "../../src/premint/ZoraCreator1155Preminter.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";

contract ZoraCreator1155PreminterTest is Test {
    ZoraCreatorFixedPriceSaleStrategy internal fixedPrice;
    ZoraCreator1155Preminter internal preminter;
    ZoraCreator1155FactoryImpl internal factory;

    ICreatorRoyaltiesControl.RoyaltyConfiguration defaultRoyaltyConfig;

    function setUp() external {
        ZoraCreator1155Impl zoraCreator1155Impl = new ZoraCreator1155Impl(0, address(0), address(0));
        ZoraCreatorFixedPriceSaleStrategy fixedPriceMinter = new ZoraCreatorFixedPriceSaleStrategy();
        factory = new ZoraCreator1155FactoryImpl(zoraCreator1155Impl, IMinter1155(address(1)), IMinter1155(address(2)), IMinter1155(address(3)));
        uint32 royaltyBPS = 2;
        uint32 royaltyMintSchedule = 20;
        address royaltyRecipient = vm.addr(4);

        defaultRoyaltyConfig = ICreatorRoyaltiesControl.RoyaltyConfiguration({
            royaltyBPS: royaltyBPS,
            royaltyRecipient: royaltyRecipient,
            royaltyMintSchedule: royaltyMintSchedule
        });

        preminter = new ZoraCreator1155Preminter();
        preminter.initialize(factory, fixedPriceMinter);
    }

    function test_successfullyMintsTokens() external {
        // setup contract config
        uint256 creatorPrivateKey = 0xA11CE;
        address creator = vm.addr(creatorPrivateKey);

        // 1. Make contract creation params

        // configuration of contract to create
        ZoraCreator1155Preminter.ContractCreationConfig memory contractConfig = ZoraCreator1155Preminter.ContractCreationConfig({
            contractAdmin: creator,
            contractName: "blah",
            contractURI: "blah.contract",
            defaultRoyaltyConfiguration: defaultRoyaltyConfig
        });
        // configuration of token to create
        ZoraCreator1155Preminter.TokenCreationConfig memory tokenConfig = ZoraCreator1155Preminter.TokenCreationConfig({
            tokenURI: "blah.token",
            tokenMaxSupply: 10,
            tokenSalesConfig: ZoraCreator1155Preminter.PremintFixedPriceSalesConfig({maxTokensPerAddress: 5, pricePerToken: 0, duration: 0})
        });
        // how many tokens are minted to the executor
        uint256 quantityToMint = 4;
        uint256 chainId = block.chainid;

        // 2. Call smart contract to get digest to sign for creation params.
        bytes32 digest = preminter.premintHashData(contractConfig, tokenConfig, chainId);

        // 3. Sign the digest
        // create a signature with the digest for the params
        bytes memory signature = _sign(creatorPrivateKey, digest);

        // this account will be used to execute the premint, and should result in a contract being created
        address premintExecutor = vm.addr(701);

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.prank(premintExecutor);
        uint256 tokenId = preminter.premint(contractConfig, tokenConfig, quantityToMint, signature);

        // get contract hash, which is unique per contract creation config, and can be used
        // retreive the address created for a contract
        uint256 contractHash = preminter.contractDataHash(contractConfig);

        // get the contract address from the preminter based on the contract hash id.
        IZoraCreator1155 created1155Contract = IZoraCreator1155(preminter.contractAddresses(contractHash));

        // get the created contract, and make sure that tokens have been minted to the address
        assertEq(created1155Contract.balanceOf(premintExecutor, tokenId), quantityToMint);

        // alter the token creation config, create a new signature with the existing
        // contract config and new token config
        tokenConfig.tokenURI = "blah2.token";
        digest = preminter.premintHashData(contractConfig, tokenConfig, chainId);
        signature = _sign(creatorPrivateKey, digest);

        // premint with new token config and signature
        vm.prank(premintExecutor);
        tokenId = preminter.premint(contractConfig, tokenConfig, quantityToMint, signature);

        // a new token shoudl have been created, with x tokens minted to the executor, on the same contract address
        // as before since the contract config didnt change
        assertEq(created1155Contract.balanceOf(premintExecutor, tokenId), quantityToMint);
    }

    function _sign(uint256 privateKey, bytes32 digest) private pure returns (bytes memory) {
        // sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // combine into a single bytes array
        return abi.encodePacked(r, s, v);
    }
}
