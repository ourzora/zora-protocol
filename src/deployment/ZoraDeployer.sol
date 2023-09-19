// spdx-license-identifier: mit
pragma solidity ^0.8.17;

import {Zora1155Factory} from "../proxies/Zora1155Factory.sol";
import {ZoraCreator1155Impl} from "../nft/ZoraCreator1155Impl.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreator1155FactoryImpl} from "../factory/ZoraCreator1155FactoryImpl.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {Deployment, ChainConfig} from "./DeploymentConfig.sol";
import {ProxyShim} from "../utils/ProxyShim.sol";
import {ZoraCreator1155PremintExecutor} from "../delegation/ZoraCreator1155PremintExecutor.sol";
import {Zora1155PremintExecutorProxy} from "../proxies/Zora1155PremintExecutorProxy.sol";
import {IImmutableCreate2Factory} from "./IImmutableCreate2Factory.sol";
import {NewFactoryProxyDeployer} from "./NewFactoryProxyDeployer.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

library ZoraDeployer {
    IImmutableCreate2Factory constant IMMUTABLE_CREATE2_FACTORY = IImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);

    function deployNew1155AndFactoryImpl(
        address factoryProxyAddress,
        address mintFeeRecipient,
        address protocolRewards,
        IMinter1155 merkleMinter,
        IMinter1155 redeemMinterFactory,
        IMinter1155 fixedPriceMinter
    ) internal returns (address factoryImplAddress, address contract1155ImplAddress) {
        ZoraCreator1155Impl creatorImpl = new ZoraCreator1155Impl(0, mintFeeRecipient, factoryProxyAddress, protocolRewards);

        contract1155ImplAddress = address(creatorImpl);

        ZoraCreator1155FactoryImpl factoryImpl = new ZoraCreator1155FactoryImpl({
            _implementation: creatorImpl,
            _merkleMinter: merkleMinter,
            _redeemMinterFactory: redeemMinterFactory,
            _fixedPriceMinter: fixedPriceMinter
        });

        factoryImplAddress = address(factoryImpl);
    }

    function newFactoryProxyDeployerCreationCode(address owner) internal pure returns (bytes memory) {
        return abi.encodePacked(type(NewFactoryProxyDeployer).creationCode, abi.encode(owner));
    }

    function deployNewPreminterImplementation(address factoryProxyAddress) internal returns (address) {
        // create preminter implementation
        ZoraCreator1155PremintExecutor preminterImplementation = new ZoraCreator1155PremintExecutor(ZoraCreator1155FactoryImpl(factoryProxyAddress));

        return address(preminterImplementation);
    }

    function determinsticFactoryDeployerAddress(address deployerAddress, bytes32 salt) internal view returns (address) {
        bytes memory newFactoryProxyDeployerInitCode = abi.encodePacked(type(NewFactoryProxyDeployer).creationCode, abi.encode(deployerAddress));

        // we can know determinstically what the address of the new factory proxy deployer will be, given it's deployed from with the salt and init code,
        // from the ImmutableCreate2Factory
        return IMMUTABLE_CREATE2_FACTORY.findCreate2Address(salt, newFactoryProxyDeployerInitCode);
    }

    function determinsticFactoryProxyAddress(bytes32 proxyShimSalt, bytes32 factoryProxySalt, address proxyDeployerAddress) internal pure returns (address) {
        address proxyShimAddress = Create2.computeAddress(
            proxyShimSalt,
            keccak256(abi.encodePacked(type(ProxyShim).creationCode, abi.encode(proxyDeployerAddress))),
            proxyDeployerAddress
        );

        return
            Create2.computeAddress(
                factoryProxySalt,
                keccak256(abi.encodePacked(type(Zora1155Factory).creationCode, abi.encode(proxyShimAddress, ""))),
                proxyDeployerAddress
            );
    }

    function determinsticFactoryDeployerAndFactoryProxyAddress(
        address deployerAddress,
        bytes32 factoryDeloyerSalt,
        bytes32 proxyShimSalt,
        bytes32 factoryProxySalt
    ) internal view returns (address factoryDeployerAddress, address factoryProxyAddress) {
        factoryDeployerAddress = determinsticFactoryDeployerAddress(deployerAddress, factoryDeloyerSalt);
        factoryProxyAddress = determinsticFactoryProxyAddress(proxyShimSalt, factoryProxySalt, factoryDeployerAddress);
    }

    function deployNewPreminterProxy(address factoryProxyAddress, address premintOwner) internal returns (address preminterProxyAddress) {
        address preminterImplementation = deployNewPreminterImplementation(factoryProxyAddress);

        // build the proxy
        Zora1155PremintExecutorProxy proxy = new Zora1155PremintExecutorProxy(preminterImplementation, "");

        // access the executor implementation via the proxy, and initialize the admin
        ZoraCreator1155PremintExecutor preminterAtProxy = ZoraCreator1155PremintExecutor(address(proxy));
        preminterAtProxy.initialize(premintOwner);

        preminterProxyAddress = address(proxy);
    }
}
