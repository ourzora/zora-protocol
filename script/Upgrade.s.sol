// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import {ZoraCreator1155FactoryImpl} from "../src/factory/ZoraCreator1155FactoryImpl.sol";
import {Zora1155Factory} from "../src/proxies/Zora1155Factory.sol";
import {ZoraCreator1155Impl} from "../src/nft/ZoraCreator1155Impl.sol";
import {ICreatorRoyaltiesControl} from "../src/interfaces/ICreatorRoyaltiesControl.sol";
import {IZoraCreator1155Factory} from "../src/interfaces/IZoraCreator1155Factory.sol";
import {IMinter1155} from "../src/interfaces/IMinter1155.sol";
import {IZoraCreator1155} from "../src/interfaces/IZoraCreator1155.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../src/minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {ZoraCreatorMerkleMinterStrategy} from "../src/minters/merkle/ZoraCreatorMerkleMinterStrategy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract UpgradeScript is Script {
    using Strings for uint256;

    string configFile;

    function _getKey(string memory key) internal view returns (address result) {
        (result) = abi.decode(vm.parseJson(configFile, key), (address));
    }

    function _getKeyNumber(string memory key) internal view returns (uint256 result) {
        (result) = abi.decode(vm.parseJson(configFile, key), (uint256));
    }

    function setUp() public {
        uint256 chainID = vm.envUint("CHAIN_ID");
        console.log("CHAIN_ID", chainID);

        console2.log("Starting ---");

        configFile = vm.readFile(string.concat("./addresses/", Strings.toString(chainID), ".json"));
    }

    function run() public {
        address payable deployer = payable(vm.envAddress("DEPLOYER"));

        vm.startBroadcast(deployer);

        ZoraCreatorFixedPriceSaleStrategy fixedPricedMinter = new ZoraCreatorFixedPriceSaleStrategy();
        ZoraCreatorMerkleMinterStrategy merkleMinter = new ZoraCreatorMerkleMinterStrategy();

        address nftImpl = _getKey("1155_IMPL");
        if (nftImpl == address(0)) {
            nftImpl = address(new ZoraCreator1155Impl(_getKeyNumber("MINT_FEE_AMOUNT"), _getKey("MINT_FEE_RECIPIENT")));
            console2.log("New NFT_IMPL", nftImpl);
        } else {
            console2.log("Existing NFT_IMPL", nftImpl);
        }

        address factoryProxy = _getKey("FACTORY_PROXY");

        ZoraCreator1155FactoryImpl factoryImpl = new ZoraCreator1155FactoryImpl({
            _implementation: IZoraCreator1155(nftImpl),
            _merkleMinter: merkleMinter,
            _fixedPriceMinter: fixedPricedMinter
        });

        console2.log("New Factory Impl", address(factoryImpl));
        console2.log("Upgrade to this new factory impl from ", factoryProxy);

        bytes[] memory setup = new bytes[](0);
        address newContract = address(
            IZoraCreator1155Factory(address(factoryProxy)).createContract(
                "ipfs://bafkreigu544g6wjvqcysurpzy5pcskbt45a5f33m6wgythpgb3rfqi3lzi",
                "+++",
                ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyBPS: 0, royaltyRecipient: address(0), royaltyMintSchedule: 0}),
                deployer,
                setup
            )
        );

        console2.log("Testing 1155 contract address", newContract);
    }
}
