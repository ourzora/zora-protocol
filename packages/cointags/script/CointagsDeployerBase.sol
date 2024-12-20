// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";

import {ProxyDeployerScript, DeterministicContractConfig, DeterministicDeployerAndCaller} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {CointagFactoryImpl} from "../src/CointagFactoryImpl.sol";
import {CointagImpl} from "../src/CointagImpl.sol";
import {IVersionedContract} from "@zoralabs/shared-contracts/interfaces/IVersionedContract.sol";
import {IUpgradeGate} from "@zoralabs/shared-contracts/interfaces/IUpgradeGate.sol";
import {UpgradeGate} from "../src/upgrades/UpgradeGate.sol";

contract CointagsDeployerBase is ProxyDeployerScript {
    address internal constant PROTOCOL_REWARDS = 0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B;

    using stdJson for string;

    struct CointagsDeployment {
        // Factory
        address cointagFactory;
        address cointagFactoryImpl;
        string cointagVersion;
        // Implementation
        address cointag;
        address upgradeGate;
    }

    function addressesFile() internal view returns (string memory) {
        return string.concat("./addresses/", vm.toString(block.chainid), ".json");
    }

    function saveDeployment(CointagsDeployment memory deployment) internal {
        string memory objectKey = "config";

        vm.serializeAddress(objectKey, "COINTAG_FACTORY", deployment.cointagFactory);
        vm.serializeAddress(objectKey, "COINTAG_FACTORY_IMPL", deployment.cointagFactoryImpl);
        vm.serializeString(objectKey, "COINTAG_VERSION", deployment.cointagVersion);
        vm.serializeAddress(objectKey, "UPGRADE_GATE", deployment.upgradeGate);

        string memory result = vm.serializeAddress(objectKey, "COINTAG", deployment.cointag);

        vm.writeJson(result, addressesFile());
    }

    function readDeployment() internal returns (CointagsDeployment memory deployment) {
        string memory file = addressesFile();
        if (!vm.exists(file)) {
            return deployment;
        }
        string memory json = vm.readFile(file);

        deployment.cointagFactory = readAddressOrDefaultToZero(json, "COINTAG_FACTORY");
        deployment.cointagFactoryImpl = readAddressOrDefaultToZero(json, "COINTAG_FACTORY_IMPL");
        deployment.cointagVersion = readStringOrDefaultToEmpty(json, "COINTAG_VERSION");
        deployment.cointag = readAddressOrDefaultToZero(json, "COINTAG");
        deployment.upgradeGate = readAddressOrDefaultToZero(json, "UPGRADE_GATE");
    }

    function deployCointagsImpl(address upgradeGate) internal returns (CointagImpl) {
        return new CointagImpl(PROTOCOL_REWARDS, getWeth(), upgradeGate);
    }

    function deployCointagFactoryImpl(address cointagsImpl) internal returns (CointagFactoryImpl) {
        return new CointagFactoryImpl(cointagsImpl);
    }

    function deployUpgradeGate(CointagsDeployment memory deployment) internal returns (IUpgradeGate) {
        UpgradeGate upgradeGate = new UpgradeGate("Cointags Upgrade Gate", "https://github.com/ourzora/zora-protocol");
        upgradeGate.transferInitialOwnership(getProxyAdmin());
        deployment.upgradeGate = address(upgradeGate);

        // validate that the upgrade gate owner is the proxy admin
        require(UpgradeGate(deployment.upgradeGate).owner() == getProxyAdmin(), "Upgrade gate owner is not the proxy admin");

        return IUpgradeGate(deployment.upgradeGate);
    }

    function deployCointagsDeterministic(CointagsDeployment memory deployment, DeterministicDeployerAndCaller deployer) internal {
        // read previously saved deterministic config
        DeterministicContractConfig memory cointagsConfig = readDeterministicContractConfig("cointagFactory");

        // Deploy implementation contracts
        deployment.cointag = address(deployCointagsImpl(deployment.upgradeGate));
        deployment.cointagFactoryImpl = address(deployCointagFactoryImpl(deployment.cointag));
        deployment.cointagVersion = IVersionedContract(deployment.cointag).contractVersion();

        if (deployment.cointagFactoryImpl.code.length == 0) {
            revert("Factory Impl not yet deployed. Make sure to deploy it with DeployImpl.s.sol");
        }

        // build upgrade to and call for factory, with init call
        bytes memory upgradeToAndCall = abi.encodeWithSelector(
            UUPSUpgradeable.upgradeToAndCall.selector,
            deployment.cointagFactoryImpl,
            abi.encodeWithSelector(CointagFactoryImpl.initialize.selector, getProxyAdmin())
        );

        // sign deployment with turnkey account
        bytes memory signature = signDeploymentWithTurnkey(cointagsConfig, upgradeToAndCall, deployer);

        printVerificationCommand(cointagsConfig);

        deployment.cointagFactory = deployer.permitSafeCreate2AndCall(
            signature,
            cointagsConfig.salt,
            cointagsConfig.creationCode,
            upgradeToAndCall,
            cointagsConfig.deployedAddress
        );

        // validate that the cointag factory owner is the proxy admin
        require(CointagFactoryImpl(deployment.cointagFactory).owner() == getProxyAdmin(), "Cointag factory owner is not the proxy admin");
    }
}
