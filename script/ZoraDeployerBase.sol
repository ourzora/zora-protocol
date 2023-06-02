// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IZoraCreator1155Factory} from "../src/interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreator1155Impl} from "../src/nft/ZoraCreator1155Impl.sol";
import {ICreatorRoyaltiesControl} from "../src/interfaces/ICreatorRoyaltiesControl.sol";

/// @notice Chain configuration for constants set manually during deploy. Does not get written to after deploys.
struct ChainConfig {
    /// @notice The user that owns the factory proxy. Allows ability to upgrade for new implementations deployed.
    address factoryOwner;
    /// @notice Mint fee amount in WEI charged for each mint
    uint256 mintFeeAmount;
    /// @notice Mint fee recipient user
    address mintFeeRecipient;
}

/// @notice Deployment addresses – set to new deployed addresses by the scripts.
struct Deployment {
    /// @notice Fixed price minter strategy configuration contract
    address fixedPriceSaleStrategy;
    /// @notice Merkle minter strategy (formerly presale) configuration
    address merkleMintSaleStrategy;
    /// @notice Redeem minter factory contract for redeem sales configurations
    address redeemMinterFactory;
    /// @notice Implementation contract for the 1155 contract
    address contract1155Impl;
    /// @notice Factory implementation contract that is the impl for the above proxy.
    address factoryImpl;
    /// @notice Factory proxy contract that creates zora drops style NFT contracts
    address factoryProxy;
    /// @notice Preminter contract that is the impl for the above proxy.
    address preminter;
}

/// @notice Deployment drops for base where
abstract contract ZoraDeployerBase is Script {
    using stdJson for string;

    /// @notice ChainID convenience getter
    /// @return id chainId
    function chainId() internal view returns (uint256 id) {
        assembly {
            id := chainid()
        }
    }

    /// @notice File used for demo metadata on verification test mint
    string constant DEMO_IPFS_METADATA_FILE = "ipfs://bafkreigu544g6wjvqcysurpzy5pcskbt45a5f33m6wgythpgb3rfqi3lzi";

    ///
    // These are the JSON key constants to standardize writing and reading configuration
    ///

    string constant FACTORY_OWNER = "FACTORY_OWNER";
    string constant MINT_FEE_AMOUNT = "MINT_FEE_AMOUNT";
    string constant MINT_FEE_RECIPIENT = "MINT_FEE_RECIPIENT";

    string constant FIXED_PRICE_SALE_STRATEGY = "FIXED_PRICE_SALE_STRATEGY";
    string constant MERKLE_MINT_SALE_STRATEGY = "MERKLE_MINT_SALE_STRATEGY";
    string constant REDEEM_MINTER_FACTORY = "REDEEM_MINTER_FACTORY";
    string constant CONTRACT_1155_IMPL = "CONTRACT_1155_IMPL";
    string constant FACTORY_IMPL = "FACTORY_IMPL";
    string constant FACTORY_PROXY = "FACTORY_PROXY";
    string constant PREMINTER = "PREMINTER";

    /// @notice Return a prefixed key for reading with a ".".
    /// @param key key to prefix
    /// @return prefixed key
    function getKeyPrefix(string memory key) internal pure returns (string memory) {
        return string.concat(".", key);
    }

    /// @notice Returns the chain configuration struct from the JSON configuration file
    /// @return chainConfig structure
    function getChainConfig() internal returns (ChainConfig memory chainConfig) {
        string memory json = vm.readFile(string.concat("chainConfigs/", Strings.toString(chainId()), ".json"));
        chainConfig.factoryOwner = json.readAddress(getKeyPrefix(FACTORY_OWNER));
        chainConfig.mintFeeAmount = json.readUint(getKeyPrefix(MINT_FEE_AMOUNT));
        chainConfig.mintFeeRecipient = json.readAddress(getKeyPrefix(MINT_FEE_RECIPIENT));
    }

    // function readAddress(string memory json, string memory key) private returns (address result) {
    //     try json.readAddress(key) returns (address _result) {
    //         result = _result;
    //     } catch {}
    // }

    /// @notice Get the deployment configuration struct from the JSON configuration file
    /// @return deployment deployment configuration structure
    function getDeployment() internal returns (Deployment memory deployment) {
        string memory json = vm.readFile(string.concat("addresses/", Strings.toString(chainId()), ".json"));
        deployment.fixedPriceSaleStrategy = json.readAddress(getKeyPrefix(FIXED_PRICE_SALE_STRATEGY));
        deployment.merkleMintSaleStrategy = json.readAddress(getKeyPrefix(MERKLE_MINT_SALE_STRATEGY));
        deployment.redeemMinterFactory = json.readAddress(getKeyPrefix(REDEEM_MINTER_FACTORY));
        deployment.contract1155Impl = json.readAddress(getKeyPrefix(CONTRACT_1155_IMPL));
        deployment.factoryImpl = json.readAddress(getKeyPrefix(FACTORY_IMPL));
        deployment.factoryProxy = json.readAddress(getKeyPrefix(FACTORY_PROXY));
        deployment.preminter = json.readAddress(getKeyPrefix(PREMINTER));
    }

    /// @notice Get deployment configuration struct as JSON
    /// @param deployment deploymet struct
    /// @return deploymentJson string JSON of the deployment info
    function getDeploymentJSON(Deployment memory deployment) internal returns (string memory deploymentJson) {
        string memory deploymentJsonKey = "deployment_json_file_key";
        vm.serializeAddress(deploymentJsonKey, FIXED_PRICE_SALE_STRATEGY, deployment.fixedPriceSaleStrategy);
        vm.serializeAddress(deploymentJsonKey, MERKLE_MINT_SALE_STRATEGY, deployment.merkleMintSaleStrategy);
        vm.serializeAddress(deploymentJsonKey, REDEEM_MINTER_FACTORY, deployment.redeemMinterFactory);
        vm.serializeAddress(deploymentJsonKey, CONTRACT_1155_IMPL, deployment.contract1155Impl);
        vm.serializeAddress(deploymentJsonKey, FACTORY_IMPL, deployment.factoryImpl);
        vm.serializeAddress(deploymentJsonKey, PREMINTER, deployment.preminter);
        deploymentJson = vm.serializeAddress(deploymentJsonKey, FACTORY_PROXY, deployment.factoryProxy);
        console2.log(deploymentJson);
    }

    /// @notice Deploy a test contract for etherscan auto-verification
    /// @param factoryProxy Factory address to use
    /// @param admin Admin owner address to use
    function deployTestContractForVerification(address factoryProxy, address admin) internal {
        bytes[] memory initUpdate = new bytes[](1);
        initUpdate[0] = abi.encodeWithSelector(
            ZoraCreator1155Impl.setupNewToken.selector,
            "ipfs://bafkreigu544g6wjvqcysurpzy5pcskbt45a5f33m6wgythpgb3rfqi3lzi",
            100
        );
        address newContract = address(
            IZoraCreator1155Factory(factoryProxy).createContract(
                "ipfs://bafybeicgolwqpozsc7iwgytavete56a2nnytzix2nb2rxefdvbtwwtnnoe/metadata",
                unicode"🪄",
                ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyBPS: 0, royaltyRecipient: address(0), royaltyMintSchedule: 0}),
                payable(admin),
                initUpdate
            )
        );
        console2.log("Deployed new contract for verification purposes", newContract);
    }
}
