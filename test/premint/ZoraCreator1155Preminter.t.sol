// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ECDSAUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/utils/cryptography/ECDSAUpgradeable.sol";

import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155} from "../../src/proxies/Zora1155.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
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
    ZoraCreator1155Preminter internal preminter;
    ZoraCreator1155FactoryImpl internal factory;
    // setup contract config
    uint256 creatorPrivateKey = 0xA11CE;
    address creator;

    ICreatorRoyaltiesControl.RoyaltyConfiguration defaultRoyaltyConfig;

    event Preminted(
        address indexed contractAddress,
        uint256 indexed tokenId,
        bool indexed createdNewContract,
        uint256 contractHashId,
        uint32 uid,
        ZoraCreator1155Preminter.ContractCreationConfig contractConfig,
        ZoraCreator1155Preminter.TokenCreationConfig tokenConfig,
        address minter,
        uint256 quantityMinted
    );

    function setUp() external {
        ZoraCreator1155Impl zoraCreator1155Impl = new ZoraCreator1155Impl(0, address(0), address(0));
        ZoraCreatorFixedPriceSaleStrategy fixedPriceMinter = new ZoraCreatorFixedPriceSaleStrategy();
        factory = new ZoraCreator1155FactoryImpl(zoraCreator1155Impl, IMinter1155(address(1)), fixedPriceMinter, IMinter1155(address(3)));
        uint32 royaltyBPS = 2;
        uint32 royaltyMintSchedule = 20;
        address royaltyRecipient = vm.addr(4);

        defaultRoyaltyConfig = ICreatorRoyaltiesControl.RoyaltyConfiguration({
            royaltyBPS: royaltyBPS,
            royaltyRecipient: royaltyRecipient,
            royaltyMintSchedule: royaltyMintSchedule
        });

        preminter = new ZoraCreator1155Preminter();
        preminter.initialize(factory);

        creatorPrivateKey = 0xA11CE;
        creator = vm.addr(creatorPrivateKey);
    }

    function makeDefaultContractCreationConfig() internal view returns (ZoraCreator1155Preminter.ContractCreationConfig memory) {
        return ZoraCreator1155Preminter.ContractCreationConfig({contractAdmin: creator, contractName: "blah", contractURI: "blah.contract"});
    }

    function makeDefaultTokenCreationConfig() internal view returns (ZoraCreator1155Preminter.TokenCreationConfig memory) {
        return
            ZoraCreator1155Preminter.TokenCreationConfig({
                tokenURI: "blah.token",
                maxSupply: 10,
                maxTokensPerAddress: 5,
                pricePerToken: 0,
                saleDuration: 0,
                royaltyMintSchedule: defaultRoyaltyConfig.royaltyMintSchedule,
                royaltyBPS: defaultRoyaltyConfig.royaltyBPS,
                royaltyRecipient: defaultRoyaltyConfig.royaltyRecipient
            });
    }

    function makeDefaultPremintConfig() internal view returns (ZoraCreator1155Preminter.PremintConfig memory) {
        return
            ZoraCreator1155Preminter.PremintConfig({
                contractConfig: makeDefaultContractCreationConfig(),
                tokenConfig: makeDefaultTokenCreationConfig(),
                uid: 100,
                version: 0
            });
    }

    function test_successfullyMintsTokens() external {
        // 1. Make contract creation params

        // configuration of contract to create
        ZoraCreator1155Preminter.PremintConfig memory premintConfig = makeDefaultPremintConfig();

        // how many tokens are minted to the executor
        uint256 quantityToMint = 4;
        uint256 chainId = block.chainid;
        string memory comment = "hi";

        // 2. Call smart contract to get digest to sign for creation params.
        bytes32 digest = preminter.premintHashData(premintConfig, address(preminter), chainId);

        // 3. Sign the digest
        // create a signature with the digest for the params
        bytes memory signature = _sign(creatorPrivateKey, digest);

        // this account will be used to execute the premint, and should result in a contract being created
        address premintExecutor = vm.addr(701);

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.prank(premintExecutor);
        (, uint256 tokenId) = preminter.premint(premintConfig, signature, quantityToMint, comment);

        // get contract hash, which is unique per contract creation config, and can be used
        // retreive the address created for a contract
        uint256 contractHash = preminter.contractDataHash(premintConfig.contractConfig);

        // get the contract address from the preminter based on the contract hash id.
        IZoraCreator1155 created1155Contract = IZoraCreator1155(preminter.contractAddresses(contractHash));

        // get the created contract, and make sure that tokens have been minted to the address
        assertEq(created1155Contract.balanceOf(premintExecutor, tokenId), quantityToMint);

        // alter the token creation config, create a new signature with the existing
        // contract config and new token config
        premintConfig.tokenConfig.tokenURI = "blah2.token";
        premintConfig.uid++;

        digest = preminter.premintHashData(premintConfig, address(preminter), chainId);
        signature = _sign(creatorPrivateKey, digest);

        // premint with new token config and signature
        vm.prank(premintExecutor);
        (, tokenId) = preminter.premint(premintConfig, signature, quantityToMint, comment);

        // a new token shoudl have been created, with x tokens minted to the executor, on the same contract address
        // as before since the contract config didnt change
        assertEq(created1155Contract.balanceOf(premintExecutor, tokenId), quantityToMint);
    }

    function test_signatureForSameContractandUid_cannotBeExecutedTwice() external {
        // 1. Make contract creation params

        // configuration of contract to create
        ZoraCreator1155Preminter.PremintConfig memory premintConfig = makeDefaultPremintConfig();

        // how many tokens are minted to the executor
        uint256 quantityToMint = 4;
        uint256 chainId = block.chainid;

        // 2. Call smart contract to get digest to sign for creation params.
        bytes32 digest = preminter.premintHashData(premintConfig, address(preminter), chainId);

        // 3. Sign the digest
        // create a signature with the digest for the params
        bytes memory signature = _sign(creatorPrivateKey, digest);

        // this account will be used to execute the premint, and should result in a contract being created
        address premintExecutor = vm.addr(701);

        string memory comment = "I love it";

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.startPrank(premintExecutor);
        preminter.premint(premintConfig, signature, quantityToMint, comment);

        // create a sig for another token with same uid, it should revert
        premintConfig.tokenConfig.tokenURI = "blah2.token";
        digest = preminter.premintHashData(premintConfig, address(preminter), chainId);
        signature = _sign(creatorPrivateKey, digest);

        // premint with new token config and signature - it should revert
        vm.expectRevert(abi.encodeWithSelector(ZoraCreator1155Preminter.TokenAlreadyCreated.selector));
        preminter.premint(premintConfig, signature, quantityToMint, comment);

        // change the version, it should still revert
        premintConfig.version++;
        digest = preminter.premintHashData(premintConfig, address(preminter), chainId);
        signature = _sign(creatorPrivateKey, digest);

        // premint with new token config and signature - it should revert
        vm.expectRevert(abi.encodeWithSelector(ZoraCreator1155Preminter.TokenAlreadyCreated.selector));
        preminter.premint(premintConfig, signature, quantityToMint, comment);

        // change the uid, it should not revert
        premintConfig.uid++;
        digest = preminter.premintHashData(premintConfig, address(preminter), chainId);
        signature = _sign(creatorPrivateKey, digest);

        preminter.premint(premintConfig, signature, quantityToMint, comment);
    }

    function test_emitsPremint_whenNewContract() external {
        ZoraCreator1155Preminter.PremintConfig memory premintConfig = makeDefaultPremintConfig();

        // how many tokens are minted to the executor
        uint256 quantityToMint = 4;
        uint256 chainId = block.chainid;

        // 2. Call smart contract to get digest to sign for creation params.
        bytes32 digest = preminter.premintHashData(premintConfig, address(preminter), chainId);

        // 3. Sign the digest
        // create a signature with the digest for the params
        bytes memory signature = _sign(creatorPrivateKey, digest);

        // this account will be used to execute the premint, and should result in a contract being created
        address premintExecutor = vm.addr(701);

        string memory comment = "I love it";

        vm.startPrank(premintExecutor);

        // we need the contract address to assert the emitted event, so lets premint, get the contract address, rollback, and premint again
        uint256 snapshot = vm.snapshot();
        (address contractAddress, uint256 tokenId) = preminter.premint(premintConfig, signature, quantityToMint, comment);
        vm.revertTo(snapshot);

        // vm.roll(currentBlock + 1);

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        bool createdNewContract = true;
        vm.expectEmit(true, true, true, true);
        emit Preminted(
            contractAddress,
            tokenId,
            createdNewContract,
            preminter.contractDataHash(premintConfig.contractConfig),
            premintConfig.uid,
            premintConfig.contractConfig,
            premintConfig.tokenConfig,
            premintExecutor,
            quantityToMint
        );
        preminter.premint(premintConfig, signature, quantityToMint, comment);
    }

    function test_onlyOwner_hasAdminRights_onCreatedToken() public {
        ZoraCreator1155Preminter.PremintConfig memory premintConfig = makeDefaultPremintConfig();

        // how many tokens are minted to the executor
        uint256 quantityToMint = 4;
        uint256 chainId = block.chainid;

        // 2. Call smart contract to get digest to sign for creation params.
        bytes32 digest = preminter.premintHashData(premintConfig, address(preminter), chainId);

        // 3. Sign the digest
        // create a signature with the digest for the params
        bytes memory signature = _sign(creatorPrivateKey, digest);

        // this account will be used to execute the premint, and should result in a contract being created
        address premintExecutor = vm.addr(701);

        string memory comment = "I love it";

        // now call the premint function, using the same config that was used to generate the digest, and the signature
        vm.prank(premintExecutor);
        (address createdContractAddress, uint256 newTokenId) = preminter.premint(premintConfig, signature, quantityToMint, comment);

        // get the contract address from the preminter based on the contract hash id.
        IZoraCreator1155 created1155Contract = IZoraCreator1155(createdContractAddress);

        ZoraCreatorFixedPriceSaleStrategy.SalesConfig memory newSalesConfig = ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
            pricePerToken: 5 ether,
            saleStart: 0,
            saleEnd: 0,
            maxTokensPerAddress: 5,
            fundsRecipient: creator
        });

        IMinter1155 fixedPrice = factory.fixedPriceMinter();

        // have the premint contract try to set the sales config - it should revert with
        // the expected UserMissingRole error
        vm.expectRevert(
            abi.encodeWithSelector(
                IZoraCreator1155.UserMissingRoleForToken.selector,
                address(preminter),
                newTokenId,
                ZoraCreator1155Impl(address(created1155Contract)).PERMISSION_BIT_SALES()
            )
        );
        vm.prank(address(preminter));
        created1155Contract.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(ZoraCreatorFixedPriceSaleStrategy.setSale.selector, newTokenId, newSalesConfig)
        );

        // have admin/creator try to set the sales config - it should succeed
        vm.prank(creator);
        created1155Contract.callSale(
            newTokenId,
            fixedPrice,
            abi.encodeWithSelector(ZoraCreatorFixedPriceSaleStrategy.setSale.selector, newTokenId, newSalesConfig)
        );

        // have the premint contract try to set royalties config - it should revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IZoraCreator1155.UserMissingRoleForToken.selector,
                address(preminter),
                newTokenId,
                ZoraCreator1155Impl(address(created1155Contract)).PERMISSION_BIT_FUNDS_MANAGER()
            )
        );
        vm.prank(address(preminter));
        created1155Contract.updateRoyaltiesForToken(newTokenId, defaultRoyaltyConfig);

        // have admin/creator try to set royalties config - it should succeed
        vm.prank(creator);
        created1155Contract.updateRoyaltiesForToken(newTokenId, defaultRoyaltyConfig);
    }

    // TODO: test that the signature must match the params

    function _sign(uint256 privateKey, bytes32 digest) private pure returns (bytes memory) {
        // sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // combine into a single bytes array
        return abi.encodePacked(r, s, v);
    }
}
