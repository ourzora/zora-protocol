// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {IZoraCreator1155Factory} from "../../src/interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreator1155FactoryImpl} from "../../src/factory/ZoraCreator1155FactoryImpl.sol";
import {IZoraCreator1155Errors} from "../../src/interfaces/IZoraCreator1155Errors.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";
import {ZoraCreator1155Impl} from "../../src/nft/ZoraCreator1155Impl.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {IOwnable} from "../../src/interfaces/IOwnable.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {MockContractMetadata} from "../mock/MockContractMetadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {ForkDeploymentConfig, Deployment} from "../../src/deployment/DeploymentConfig.sol";

contract ZoraCreator1155FactoryForkTest is ForkDeploymentConfig, Test {
    uint256 constant quantityToMint = 3;
    uint256 constant tokenMaxSupply = 100;
    uint32 constant royaltyMintSchedule = 10;
    uint32 constant royaltyBPS = 100;
    uint256 constant mintFee = 0.000777 ether;

    address collector;
    address creator;

    uint256 public constant PERMISSION_BIT_MINTER = 2 ** 2;

    function setUp() external {
        creator = vm.addr(1);
        collector = vm.addr(2);
    }

    /// @notice gets the chains to do fork tests on, by reading environment var FORK_TEST_CHAINS.
    /// Chains are by name, and must match whats under `rpc_endpoints` in the foundry.toml
    function getForkTestChains() private view returns (string[] memory result) {
        try vm.envString("FORK_TEST_CHAINS", ",") returns (string[] memory forkTestChains) {
            result = forkTestChains;
        } catch {
            console.log("could not get fork test chains - make sure the environment variable FORK_TEST_CHAINS is set");
            result = new string[](0);
        }
    }

    function _setupToken(IZoraCreator1155 target, IMinter1155 fixedPrice, uint96 tokenPrice) private returns (uint256 tokenId) {
        string memory tokenURI = "ipfs://token";

        tokenId = target.setupNewToken(tokenURI, tokenMaxSupply);

        target.addPermission(tokenId, address(fixedPrice), PERMISSION_BIT_MINTER);

        target.callSale(
            tokenId,
            fixedPrice,
            abi.encodeWithSelector(
                ZoraCreatorFixedPriceSaleStrategy.setSale.selector,
                tokenId,
                ZoraCreatorFixedPriceSaleStrategy.SalesConfig({
                    pricePerToken: tokenPrice,
                    saleStart: 0,
                    saleEnd: type(uint64).max,
                    maxTokensPerAddress: 0,
                    fundsRecipient: address(0)
                })
            )
        );
    }

    function _createErc1155Contract(IZoraCreator1155Factory factory) private returns (IZoraCreator1155 target) {
        // create the contract, with no toekns
        bytes[] memory initSetup = new bytes[](0);

        address admin = creator;
        string memory contractURI = "ipfs://asdfasdf";
        string memory name = "Test";
        address royaltyRecipient = creator;

        address deployedAddress = factory.createContract(
            contractURI,
            name,
            ICreatorRoyaltiesControl.RoyaltyConfiguration({
                royaltyBPS: royaltyBPS,
                royaltyRecipient: royaltyRecipient,
                royaltyMintSchedule: royaltyMintSchedule
            }),
            payable(admin),
            initSetup
        );

        target = IZoraCreator1155(deployedAddress);

        // ** 2. Setup a new token with the fixed price sales strategy **
    }

    function mintTokenAtFork(IZoraCreator1155Factory factory) internal {
        uint96 tokenPrice = 1 ether;
        IMinter1155 fixedPrice = factory.defaultMinters()[0];
        // now create a contract with the factory
        vm.startPrank(creator);

        // ** 1. Create the erc1155 contract **
        IZoraCreator1155 target = _createErc1155Contract(factory);

        // ** 2. Setup a new token with the fixed price sales strategy and the token price **
        uint256 tokenId = _setupToken(target, fixedPrice, tokenPrice);

        // ** 3. Mint on that contract **

        // mint 3 tokens
        uint256 valueToSend = quantityToMint * (tokenPrice + mintFee);

        // mint the token
        vm.deal(collector, valueToSend);
        vm.startPrank(collector);
        ZoraCreator1155Impl(address(target)).mintWithRewards{value: valueToSend}(fixedPrice, tokenId, quantityToMint, abi.encode(collector), address(0));

        uint256 balance = ZoraCreator1155Impl(address(target)).balanceOf(collector, tokenId);

        assertEq(balance, quantityToMint, "balance mismatch");
    }

    function testTheFork(string memory chainName) private {
        console.log("testing on fork: ", chainName);

        // create and select the fork, which will be used for all subsequent calls
        // it will also affect the current block chain id based on the rpc url returned
        vm.createSelectFork(vm.rpcUrl(chainName));

        Deployment memory deployment = getDeployment();

        address factoryAddress = deployment.factoryProxy;
        ZoraCreator1155FactoryImpl factory = ZoraCreator1155FactoryImpl(factoryAddress);

        assertEq(factory.implementation(), deployment.factoryImpl, "factory implementation incorrect");

        assertEq(getChainConfig().factoryOwner, IOwnable(factoryAddress).owner(), string.concat("configured owner incorrect on: ", chainName));

        // make sure that the address from the factory matches the stored fixed price address
        // sanity check - check minters match config
        assertEq(address(factory.merkleMinter()), deployment.merkleMintSaleStrategy);
        assertEq(address(factory.fixedPriceMinter()), deployment.fixedPriceSaleStrategy);
        assertEq(address(factory.redeemMinterFactory()), deployment.redeemMinterFactory);
    }

    function test_fork_canCreateContractAndMint() external {
        string[] memory forkTestChains = getForkTestChains();
        for (uint256 i = 0; i < forkTestChains.length; i++) {
            testTheFork(forkTestChains[i]);
        }
    }

    // this is a temporary test to simulate the upgrade to the correct factory implementation
    // on zora goerli. it can be deleted post upgrade
    function test_fork_zoraGoerli_factoryUpgradeCanMint() external {
        // create and select the fork, which will be used for all subsequent calls
        // it will also affect the current block chain id based on the rpc url returned
        vm.createSelectFork(vm.rpcUrl("zora_goerli"));

        Deployment memory deployment = getDeployment();

        address factoryAddress = deployment.factoryProxy;
        ZoraCreator1155FactoryImpl factory = ZoraCreator1155FactoryImpl(factoryAddress);

        vm.prank(factory.owner());

        factory.upgradeTo(deployment.factoryImpl);

        // sanity check - check minters match config
        assertEq(address(factory.merkleMinter()), deployment.merkleMintSaleStrategy);
        assertEq(address(factory.fixedPriceMinter()), deployment.fixedPriceSaleStrategy);
        assertEq(address(factory.redeemMinterFactory()), deployment.redeemMinterFactory);

        mintTokenAtFork(factory);
    }
}
