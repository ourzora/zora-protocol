// spdx-license-identifier: mit
pragma solidity >=0.8.17;

import {Zora1155Factory} from "../proxies/Zora1155Factory.sol";
import {ZoraCreator1155Impl} from "../nft/ZoraCreator1155Impl.sol";
import {IZoraCreator1155Factory} from "../interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreator1155FactoryImpl} from "../factory/ZoraCreator1155FactoryImpl.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {Deployment, ChainConfig} from "./DeploymentConfig.sol";
import {ProxyShim} from "../utils/ProxyShim.sol";
import {ZoraCreator1155PremintExecutorImpl} from "../delegation/ZoraCreator1155PremintExecutorImpl.sol";
import {DeterministicProxyDeployer} from "./DeterministicProxyDeployer.sol";
import {ZoraCreatorFixedPriceSaleStrategy} from "../minters/fixed-price/ZoraCreatorFixedPriceSaleStrategy.sol";
import {ZoraCreatorMerkleMinterStrategy} from "../minters/merkle/ZoraCreatorMerkleMinterStrategy.sol";
import {ZoraCreatorRedeemMinterFactory} from "../minters/redeem/ZoraCreatorRedeemMinterFactory.sol";
import {ERC20Minter} from "../minters/erc20/ERC20Minter.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ICreatorRoyaltiesControl} from "../interfaces/ICreatorRoyaltiesControl.sol";
import {UpgradeGate} from "../upgrades/UpgradeGate.sol";
import {UUPSUpgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";

struct Create2Deployment {
    address deployerAddress;
    bytes32 salt;
    bytes constructorArguments;
    address deployedAddress;
}

library ZoraDeployerUtils {
    bytes32 constant IMMUTABLE_CREATE_2_FRIENDLY_SALT = bytes32(0x0000000000000000000000000000000000000000000000000000000000000001);

    function ensureValidUpgradeGate(address upgradeGateAddress) internal pure {
        require(
            keccak256(abi.encodePacked(UpgradeGate(upgradeGateAddress).contractName())) == keccak256(abi.encodePacked("ZORA 1155 Upgrade Gate")),
            "INVALID_UPGRADE_GATE"
        );
    }

    function deployNew1155AndFactoryImpl(
        address upgradeGateAddress,
        address mintFeeRecipient,
        address protocolRewards,
        address timedSaleStrategy,
        IMinter1155 merkleMinter,
        IMinter1155 redeemMinterFactory,
        IMinter1155 fixedPriceMinter
    ) internal returns (address factoryImplAddress, address contract1155ImplAddress, string memory contract1155ImplVersion) {
        ensureValidUpgradeGate(upgradeGateAddress);

        ZoraCreator1155Impl zoraCreator1155Impl = new ZoraCreator1155Impl(mintFeeRecipient, upgradeGateAddress, protocolRewards, timedSaleStrategy);

        contract1155ImplVersion = zoraCreator1155Impl.contractVersion();

        contract1155ImplAddress = address(zoraCreator1155Impl);
        factoryImplAddress = address(
            new ZoraCreator1155FactoryImpl({
                _zora1155Impl: zoraCreator1155Impl,
                _merkleMinter: merkleMinter,
                _redeemMinterFactory: redeemMinterFactory,
                _fixedPriceMinter: fixedPriceMinter
            })
        );
    }

    function deployErc20Minter(ChainConfig memory chainConfig) internal returns (address erc20Minter) {
        ERC20Minter minter = new ERC20Minter();
        // todo: load these from config
        uint256 rewardPct = 5;
        uint256 ethReward = 0.000111 ether;
        minter.initialize(chainConfig.mintFeeRecipient, chainConfig.factoryOwner, rewardPct, ethReward);

        return address(minter);
    }

    function deployMinters(
        ChainConfig memory chainConfig
    ) internal returns (address fixedPriceMinter, address merkleMinter, address redeemMinterFactory, address erc20Minter) {
        fixedPriceMinter = ImmutableCreate2FactoryUtils.safeCreate2OrGetExisting(
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000001),
            type(ZoraCreatorFixedPriceSaleStrategy).creationCode
        );

        merkleMinter = ImmutableCreate2FactoryUtils.safeCreate2OrGetExisting(
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000001),
            type(ZoraCreatorMerkleMinterStrategy).creationCode
        );

        redeemMinterFactory = ImmutableCreate2FactoryUtils.safeCreate2OrGetExisting(
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000001),
            type(ZoraCreatorRedeemMinterFactory).creationCode
        );

        erc20Minter = deployErc20Minter(chainConfig);
    }

    // we dont care what this salt is, as long as it's the same for all deployments and it has first 20 bytes of 0
    // so that anyone can deploy it
    bytes32 constant FACTORY_DEPLOYER_DEPLOYMENT_SALT = bytes32(0x0000000000000000000000000000000000000000668d7f9ed18e35000dbaba0f);

    function deployNewPreminterImplementationDeterminstic(address factoryProxyAddress) internal returns (address) {
        // create preminter implementation
        bytes memory creationCode = abi.encodePacked(type(ZoraCreator1155PremintExecutorImpl).creationCode, abi.encode(factoryProxyAddress));

        bytes32 salt = bytes32(0x0000000000000000000000000000000000000000668d7f9ec18e35000dbaba0e);

        return ImmutableCreate2FactoryUtils.safeCreate2OrGetExisting(salt, creationCode);
    }

    function deterministicFactoryDeployerAddress() internal view returns (address) {
        // we can know deterministically what the address of the new factory proxy deployer will be, given it's deployed from with the salt and init code,
        // from the ImmutableCreate2Factory
        return
            ImmutableCreate2FactoryUtils.IMMUTABLE_CREATE2_FACTORY.findCreate2Address(
                FACTORY_DEPLOYER_DEPLOYMENT_SALT,
                type(DeterministicProxyDeployer).creationCode
            );
    }

    function factoryProxyConstructorArguments(bytes32 proxyShimSalt, address proxyDeployerAddress) internal pure returns (bytes memory) {
        address proxyShimAddress = Create2.computeAddress(
            proxyShimSalt,
            keccak256(abi.encodePacked(type(ProxyShim).creationCode, abi.encode(proxyDeployerAddress))),
            proxyDeployerAddress
        );

        return abi.encode(proxyShimAddress, "");
    }

    function deterministicFactoryProxyAddress(bytes32 proxyShimSalt, bytes32 factoryProxySalt, address proxyDeployerAddress) internal pure returns (address) {
        bytes memory constructorArguments = factoryProxyConstructorArguments(proxyShimSalt, proxyDeployerAddress);

        return
            Create2.computeAddress(
                factoryProxySalt,
                keccak256(abi.encodePacked(type(Zora1155Factory).creationCode, constructorArguments)),
                proxyDeployerAddress
            );
    }

    error MismatchedAddress(address expected, address actual);

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
}
