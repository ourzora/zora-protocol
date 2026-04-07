// spdx-license-identifier: mit
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {ZoraSparksManagerImpl} from "../src/ZoraSparksManagerImpl.sol";
import {IZoraSparks1155} from "../src/interfaces/IZoraSparks1155.sol";
import {SponsoredSparksSpender} from "../src/helpers/SponsoredSparksSpender.sol";
import {SparksDeploymentConfig, SparksDeployment} from "../src/deployment/SparksDeploymentConfig.sol";
import {ProxyDeployerUtils} from "@zoralabs/shared-contracts/deployment/ProxyDeployerUtils.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";
import {ProxyDeployerScript, DeterministicDeployerAndCaller, DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";

/// @dev Deploys a new sparks spender contract
contract DeploySponsoredSparksSpender is SparksDeploymentConfig {
    function run() public {
        SparksDeployment memory deploymentConfig = getDeployment();

        vm.startBroadcast();

        address sparksAddress = address(0);
        if (block.chainid == 7777777) {
            sparksAddress = address(0x7777777b3eA6C126942BB14dD5C3C11D365C385D);
        }

        address[] memory verifiedSigners = new address[](2);

        // prod signer
        verifiedSigners[0] = address(0xD517b5cE58DCb810B42808C7da978E38aB9fcC3F);
        // dev signer
        verifiedSigners[1] = address(0xdfBFFcB12E16507313522bB00A3CD9f17dc5F38D);

        address admin = getProxyAdmin();
        require(admin != address(0), "admin cannot be none");

        console2.log("Admin:", admin);
        console2.log("Sparks:", sparksAddress);
        console2.log("Deploying to ", block.chainid);

        SponsoredSparksSpender sponsoredSparksSpender = new SponsoredSparksSpender(IZoraSparks1155(sparksAddress), admin, verifiedSigners);

        vm.stopBroadcast();

        deploymentConfig.sponsoredSparksSpender = address(sponsoredSparksSpender);
        deploymentConfig.sponsoredSparksSpenderVersion = sponsoredSparksSpender.contractVersion();

        // save sparks deployment config
        saveDeployment(deploymentConfig);
    }
}
