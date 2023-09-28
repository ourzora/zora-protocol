// spdx-license-identifier: mit
pragma solidity ^0.8.17;

import {Zora1155Factory} from "../proxies/Zora1155Factory.sol";
import {ZoraCreator1155Impl} from "../nft/ZoraCreator1155Impl.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreator1155FactoryImpl} from "../factory/ZoraCreator1155FactoryImpl.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {Deployment, ChainConfig} from "./DeploymentConfig.sol";
import {ProxyShim} from "../utils/ProxyShim.sol";
import {ZoraCreator1155PremintExecutorImpl} from "../delegation/ZoraCreator1155PremintExecutorImpl.sol";
import {IImmutableCreate2Factory} from "./IImmutableCreate2Factory.sol";
import {DeterministicProxyDeployer} from "./DeterministicProxyDeployer.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

library ZoraDeployerUtils {
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
            _zora1155Impl: creatorImpl,
            _merkleMinter: merkleMinter,
            _redeemMinterFactory: redeemMinterFactory,
            _fixedPriceMinter: fixedPriceMinter
        });

        factoryImplAddress = address(factoryImpl);
    }

    // we dont care what this salt is, as long as it's the same for all deployments and it has first 20 bytes of 0
    // so that anyone can deploy it
    bytes32 constant FACTORY_DEPLOYER_DEPLOYMENT_SALT = bytes32(0x0000000000000000000000000000000000000000668d7f9ec18e35000dbaba0e);

    function createDeterministicFactoryProxyDeployer() internal returns (DeterministicProxyDeployer) {
        return DeterministicProxyDeployer(IMMUTABLE_CREATE2_FACTORY.safeCreate2(FACTORY_DEPLOYER_DEPLOYMENT_SALT, type(DeterministicProxyDeployer).creationCode));
    }

    function deployNewPreminterImplementation(address factoryProxyAddress) internal returns (address) {
        // create preminter implementation
        ZoraCreator1155PremintExecutorImpl preminterImplementation = new ZoraCreator1155PremintExecutorImpl(ZoraCreator1155FactoryImpl(factoryProxyAddress));

        return address(preminterImplementation);
    }

    function deterministicFactoryDeployerAddress() internal view returns (address) {
        // we can know deterministically what the address of the new factory proxy deployer will be, given it's deployed from with the salt and init code,
        // from the ImmutableCreate2Factory
        return IMMUTABLE_CREATE2_FACTORY.findCreate2Address(FACTORY_DEPLOYER_DEPLOYMENT_SALT, type(DeterministicProxyDeployer).creationCode);
    }

    function deterministicFactoryProxyAddress(bytes32 proxyShimSalt, bytes32 factoryProxySalt, address proxyDeployerAddress) internal pure returns (address) {
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
}
