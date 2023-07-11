// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IZoraCreator1155Factory} from "../src/interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreator1155Impl} from "../src/nft/ZoraCreator1155Impl.sol";
import {ICreatorRoyaltiesControl} from "../src/interfaces/ICreatorRoyaltiesControl.sol";
import {ScriptDeploymentConfig, Deployment} from "../src/deployment/DeploymentConfig.sol";

/// @notice Deployment drops for base where
abstract contract ZoraDeployerBase is ScriptDeploymentConfig, Script {
    using stdJson for string;

    /// @notice File used for demo metadata on verification test mint
    string constant DEMO_IPFS_METADATA_FILE = "ipfs://bafkreigu544g6wjvqcysurpzy5pcskbt45a5f33m6wgythpgb3rfqi3lzi";

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
