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
import {ZoraCreatorFixedPriceSaleStrategy} from "../minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {ZoraCreatorMerkleMinterStrategy} from "../minters/merkle/ZoraCreatorMerkleMinterStrategy.sol";
import {ZoraCreatorRedeemMinterFactory} from "../minters/redeem/ZoraCreatorRedeemMinterFactory.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";

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
        ZoraCreator1155Impl creatorImpl = new ZoraCreator1155Impl(mintFeeRecipient, factoryProxyAddress, protocolRewards);

        contract1155ImplAddress = address(creatorImpl);

        ZoraCreator1155FactoryImpl factoryImpl = new ZoraCreator1155FactoryImpl({
            _zora1155Impl: creatorImpl,
            _merkleMinter: merkleMinter,
            _redeemMinterFactory: redeemMinterFactory,
            _fixedPriceMinter: fixedPriceMinter
        });

        factoryImplAddress = address(factoryImpl);
    }

    function deployMinters() internal returns (address fixedPriceMinter, address merkleMinter, address redeemMinterFactory) {
        fixedPriceMinter = IMMUTABLE_CREATE2_FACTORY.safeCreate2(
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000001),
            type(ZoraCreatorFixedPriceSaleStrategy).creationCode
        );

        merkleMinter = IMMUTABLE_CREATE2_FACTORY.safeCreate2(
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000001),
            type(ZoraCreatorMerkleMinterStrategy).creationCode
        );

        redeemMinterFactory = IMMUTABLE_CREATE2_FACTORY.safeCreate2(
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000001),
            type(ZoraCreatorRedeemMinterFactory).creationCode
        );
    }

    // we dont care what this salt is, as long as it's the same for all deployments and it has first 20 bytes of 0
    // so that anyone can deploy it
    bytes32 constant FACTORY_DEPLOYER_DEPLOYMENT_SALT = bytes32(0x0000000000000000000000000000000000000000668d7f9ed18e35000dbaba0f);

    function createDeterministicFactoryProxyDeployer() internal returns (DeterministicProxyDeployer) {
        return
            DeterministicProxyDeployer(IMMUTABLE_CREATE2_FACTORY.safeCreate2(FACTORY_DEPLOYER_DEPLOYMENT_SALT, type(DeterministicProxyDeployer).creationCode));
    }

    function deployNewPreminterImplementationDeterminstic(address factoryProxyAddress) internal returns (address) {
        // create preminter implementation
        bytes memory creationCode = abi.encodePacked(type(ZoraCreator1155PremintExecutorImpl).creationCode, abi.encode(factoryProxyAddress));

        address preminterImplementation = IMMUTABLE_CREATE2_FACTORY.safeCreate2(
            bytes32(0x0000000000000000000000000000000000000000668d7f9ec18e35000dbaba0e),
            creationCode
        );

        return preminterImplementation;
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

    /// @notice Deploy a test contract for etherscan auto-verification
    /// @param factoryProxy Factory address to use
    /// @param admin Admin owner address to use
    function deployTestContractForVerification(address factoryProxy, address admin) internal returns (address) {
        bytes[] memory initUpdate = new bytes[](1);
        initUpdate[0] = abi.encodeWithSelector(
            ZoraCreator1155Impl.setupNewToken.selector,
            "ipfs://bafkreigu544g6wjvqcysurpzy5pcskbt45a5f33m6wgythpgb3rfqi3lzi",
            100
        );
        return
            address(
                IZoraCreator1155Factory(factoryProxy).createContract(
                    "ipfs://bafybeicgolwqpozsc7iwgytavete56a2nnytzix2nb2rxefdvbtwwtnnoe/metadata",
                    unicode"🪄",
                    ICreatorRoyaltiesControl.RoyaltyConfiguration({royaltyBPS: 0, royaltyRecipient: address(0), royaltyMintSchedule: 0}),
                    payable(admin),
                    initUpdate
                )
            );
    }

    function testPremintSigningAndExecution(address preminterProxyAddress, address creatorAddress, uint256 creatorPrivateKey) internal {}
}
