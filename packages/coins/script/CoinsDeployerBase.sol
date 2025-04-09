// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

import {ProxyDeployerScript, DeterministicContractConfig, DeterministicDeployerAndCaller} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ZoraFactoryImpl} from "../src/ZoraFactoryImpl.sol";
import {Coin} from "../src/Coin.sol";
import {IVersionedContract} from "@zoralabs/shared-contracts/interfaces/IVersionedContract.sol";

contract CoinsDeployerBase is ProxyDeployerScript {
    address internal constant PROTOCOL_REWARDS = 0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B;

    using stdJson for string;

    struct CoinsDeployment {
        // Factory
        address zoraFactory;
        address zoraFactoryImpl;
        // Implementation
        address coinImpl;
        string coinVersion;
    }

    function addressesFile() internal view returns (string memory) {
        return string.concat("./addresses/", vm.toString(block.chainid), ".json");
    }

    function saveDeployment(CoinsDeployment memory deployment) internal {
        string memory objectKey = "config";

        vm.serializeAddress(objectKey, "ZORA_FACTORY", deployment.zoraFactory);
        vm.serializeAddress(objectKey, "ZORA_FACTORY_IMPL", deployment.zoraFactoryImpl);
        vm.serializeString(objectKey, "COIN_VERSION", deployment.coinVersion);
        string memory result = vm.serializeAddress(objectKey, "COIN_IMPL", deployment.coinImpl);

        vm.writeJson(result, addressesFile());
    }

    function readDeployment() internal returns (CoinsDeployment memory deployment) {
        string memory file = addressesFile();
        if (!vm.exists(file)) {
            return deployment;
        }
        string memory json = vm.readFile(file);

        deployment.zoraFactory = readAddressOrDefaultToZero(json, "ZORA_FACTORY");
        deployment.zoraFactoryImpl = readAddressOrDefaultToZero(json, "ZORA_FACTORY_IMPL");
        deployment.coinImpl = readAddressOrDefaultToZero(json, "COIN_IMPL");
        deployment.coinVersion = readStringOrDefaultToEmpty(json, "COIN_VERSION");
    }

    function deployCoinImpl() internal returns (Coin) {
        return new Coin(getZoraRecipient(), PROTOCOL_REWARDS, getWeth(), getUniswapV3Factory(), getUniswapSwapRouter(), getDopplerAirlock());
    }

    function deployZoraFactoryImpl(address coinImpl) internal returns (ZoraFactoryImpl) {
        return new ZoraFactoryImpl(coinImpl);
    }

    function deployImpls(CoinsDeployment memory deployment) internal returns (CoinsDeployment memory) {
        // Deploy implementation contracts
        deployment.coinImpl = address(deployCoinImpl());
        deployment.zoraFactoryImpl = address(deployZoraFactoryImpl(deployment.coinImpl));
        deployment.coinVersion = IVersionedContract(deployment.coinImpl).contractVersion();

        return deployment;
    }

    function deployZoraDeterministic(CoinsDeployment memory deployment, DeterministicDeployerAndCaller deployer) internal {
        // read previously saved deterministic config
        DeterministicContractConfig memory zoraConfig = readDeterministicContractConfig("zoraFactory");

        deployment = deployImpls(deployment);

        if (deployment.zoraFactoryImpl.code.length == 0) {
            revert("Factory Impl not yet deployed. Make sure to deploy it with DeployImpl.s.sol");
        }

        // build upgrade to and call for factory, with init call
        bytes memory upgradeToAndCall = abi.encodeWithSelector(
            UUPSUpgradeable.upgradeToAndCall.selector,
            deployment.zoraFactoryImpl,
            abi.encodeWithSelector(ZoraFactoryImpl.initialize.selector, getProxyAdmin())
        );

        // sign deployment with turnkey account
        bytes memory signature = signDeploymentWithTurnkey(zoraConfig, upgradeToAndCall, deployer);

        printVerificationCommand(zoraConfig);

        deployment.zoraFactory = deployer.permitSafeCreate2AndCall(
            signature,
            zoraConfig.salt,
            zoraConfig.creationCode,
            upgradeToAndCall,
            zoraConfig.deployedAddress
        );

        // validate that the zora factory owner is the proxy admin
        require(ZoraFactoryImpl(deployment.zoraFactory).owner() == getProxyAdmin(), "Zora factory owner is not the proxy admin");
    }
}
