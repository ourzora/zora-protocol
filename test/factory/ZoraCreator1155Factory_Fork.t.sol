// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {IZoraCreator1155Factory} from "../../src/interfaces/IZoraCreator1155Factory.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {IOwnable} from "../../src/interfaces/IOwnable.sol";
import {ICreatorRoyaltiesControl} from "../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {MockContractMetadata} from "../mock/MockContractMetadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {MintFeeManager} from "../../src/fee/MintFeeManager.sol";

import {ForkDeploymentConfig} from "../../src/deployment/DeploymentConfig.sol";

contract ZoraCreator1155FactoryForkTest is ForkDeploymentConfig, Test {
    address collector;
    address creator;

    uint256 public constant PERMISSION_BIT_MINTER = 2 ** 2;

    function setUp() external {
        creator = vm.addr(1);
        collector = vm.addr(2);
    }

    /// @notice gets the chains to do fork tests on, by reading environment var FORK_TEST_CHAINS.
    /// Chains are by name, and must match whats under `rpc_endpoints` in the foundry.toml
    function getForkTestChains() public view returns (string[] memory result) {
        try vm.envString("FORK_TEST_CHAINS", ",") returns (string[] memory forkTestChains) {
            result = forkTestChains;
        } catch {
            console.log("could not get fork test chains - make sure the environment variable FORK_TEST_CHAINS is set");
        }
    }

    function testTheFork(string memory chainName) private {
        console.log("testing on fork: ", chainName);

        // create and select the fork, which will be used for all subsequent calls
        // it will also affect the current block chain id based on the rpc url returned
        vm.createSelectFork(vm.rpcUrl(chainName));

        address factoryAddress = getDeployment().factoryProxy;
        IZoraCreator1155Factory factory = IZoraCreator1155Factory(factoryAddress);

        assertEq(IOwnable(factoryAddress).owner(), getChainConfig().factoryOwner, chainName);

        address admin = creator;
        uint32 royaltyMintSchedule = 10;
        uint32 royaltyBPS = 100;
        string memory contractURI = "ipfs://asdfasdf";
        string memory name = "Test";
        address royaltyRecipient = creator;

        string memory tokenURI = "ipfs://token";
        uint256 tokenMaxSupply = 100;

        // now create a contract with the factory
        vm.startPrank(creator);

        IMinter1155 fixedPrice = factory.defaultMinters()[0];

        // make sure that the address from the factory matches the stored fixed price address
        assertEq(address(fixedPrice), getDeployment().fixedPriceSaleStrategy, chainName);

        // ** 1. Create the erc1155 contract **

        // create the contract, with no toekns
        bytes[] memory initSetup = new bytes[](0);
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

        IZoraCreator1155 target = IZoraCreator1155(deployedAddress);

        // ** 2. Setup a new token with the fixed price sales strategy **

        uint256 tokenId = target.setupNewToken(tokenURI, tokenMaxSupply);

        target.addPermission(tokenId, address(fixedPrice), PERMISSION_BIT_MINTER);

        uint96 tokenPrice = 1 ether;

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

        // ** 3. Mint on that contract **

        // get the mint fee from the contract
        uint256 mintFee = MintFeeManager(address(target)).mintFee();

        // make sure the mint fee amount matches the configured mint fee amount
        assertEq(mintFee, getChainConfig().mintFeeAmount, chainName);

        // mint 3 tokens

        uint256 quantityToMint = 3;
        uint256 valueToSend = quantityToMint * (tokenPrice + mintFee);

        // mint the token
        vm.deal(collector, valueToSend);
        vm.prank(collector);
        target.mint{value: valueToSend}(fixedPrice, tokenId, quantityToMint, abi.encode(collector));

        assertEq(target.balanceOf(collector, tokenId), quantityToMint, chainName);
    }

    function test_canCreateContractAndMint() external {
        string[] memory forkTestChains = getForkTestChains();
        for (uint256 i = 0; i < forkTestChains.length; i++) {
            testTheFork(forkTestChains[i]);
        }
    }
}
