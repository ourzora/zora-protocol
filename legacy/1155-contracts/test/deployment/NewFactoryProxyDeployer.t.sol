// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {Zora1155Factory} from "../../src/proxies/Zora1155Factory.sol";
import {ZoraDeployerUtils, Create2Deployment} from "../../src/deployment/ZoraDeployerUtils.sol";
import {DeterministicProxyDeployer} from "../../src/deployment/DeterministicProxyDeployer.sol";
import {ProxyShim} from "../../src/utils/ProxyShim.sol";
import {UpgradeGate} from "../../src/upgrades/UpgradeGate.sol";
import {Deployment, ChainConfig} from "../../src/deployment/DeploymentConfig.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {DeterministicDeployerScript, DeterministicParams} from "../../src/deployment/DeterministicDeployerScript.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";

contract DeterministicProxyDeployerTest is DeterministicDeployerScript, Test {
    using stdJson for string;

    // the values in this test can be determined by running the script GetDeterministicParam.s.sol,
    // and copying the output values here.
    function _deployKnownZoraFactoryProxy(bytes32 salt) internal returns (DeterministicProxyDeployer) {
        // create new factory deployer using ImmutableCreate2Factory
        return DeterministicProxyDeployer(ImmutableCreate2FactoryUtils.safeCreate2OrGetExisting(salt, type(DeterministicProxyDeployer).creationCode));
    }

    function create1155FactoryImpl() internal returns (address) {
        address mintFeeRecipient = makeAddr("mintFeeRecipient");
        address protocolRewards = makeAddr("protocolRewards");

        (address factoryImplDeployment, , ) = ZoraDeployerUtils.deployNew1155AndFactoryImpl({
            upgradeGateAddress: address(new UpgradeGate()),
            mintFeeRecipient: mintFeeRecipient,
            protocolRewards: protocolRewards,
            merkleMinter: IMinter1155(address(0)),
            redeemMinterFactory: IMinter1155(address(0)),
            fixedPriceMinter: IMinter1155(address(0)),
            timedSaleStrategy: address(0)
        });

        return factoryImplDeployment;
    }

    function test_proxyCanByDeployedAtDesiredAddress(bytes32 proxySalt) external {
        vm.createSelectFork("zora_sepolia", 5271587);
        // ensure nonce is greater than current account's nonce

        (address deployerAddress, uint256 deployerPrivateKey) = makeAddrAndKey("deployer");
        bytes32 proxyDeployerSalt = ZoraDeployerUtils.FACTORY_DEPLOYER_DEPLOYMENT_SALT;

        // now we can create the implementation, pointing it to the expected deterministic address:
        bytes32 proxyShimSalt = saltWithAddressInFirst20Bytes(deployerAddress, 10);

        // 1. Create implementation contracts based on deterministic factory proxy address

        // create 1155 and factory impl, we can know the deterministic factor proxy address ahead of time:
        address factoryImplAddress = create1155FactoryImpl();

        // 2. Create factory deployer at deterministic address
        DeterministicProxyDeployer factoryProxyDeployer = _deployKnownZoraFactoryProxy(proxyDeployerSalt);

        bytes memory factoryProxyCreationCode = type(Zora1155Factory).creationCode;
        address mintFeeRecipient = makeAddr("mintFeeRecipient");

        bytes32 digest = factoryProxyDeployer.hashedDigestFactoryProxy(
            proxyShimSalt,
            proxySalt,
            factoryProxyCreationCode,
            factoryImplAddress,
            mintFeeRecipient
        );

        // sign the message
        bytes memory signature = signAndMakeBytes(digest, deployerPrivateKey);

        address expectedFactoryProxyAddress = ZoraDeployerUtils.deterministicFactoryProxyAddress(proxyShimSalt, proxySalt, address(factoryProxyDeployer));

        // now do it as original deployer, it should succeed:
        address factoryProxyAddress = factoryProxyDeployer.createFactoryProxyDeterministic(
            proxyShimSalt,
            proxySalt,
            factoryProxyCreationCode,
            expectedFactoryProxyAddress,
            factoryImplAddress,
            mintFeeRecipient,
            signature
        );

        // we know this salt from a script we ran that will generated
        // create factory proxy, using deterministic address and known salt to get proper expected address:
        assertEq(factoryProxyAddress, expectedFactoryProxyAddress, "factory proxy address wrong");
    }

    function signAndMakeBytes(bytes32 digest, uint256 privateKey) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // combine into a single bytes array
        return abi.encodePacked(r, s, v);
    }

    function test_genericContractCanByDeployedAtDesiredAddress(uint32 nonce) external {
        vm.createSelectFork("zora_sepolia", 5271587);

        (address deployerAddress, uint256 deployerPrivateKey) = makeAddrAndKey("deployer");

        vm.assume(nonce > vm.getNonce(deployerAddress));
        // we set the nonce to a random value, to prove this doesn't affect the deterministic address
        vm.setNonce(deployerAddress, nonce);

        DeterministicProxyDeployer factoryProxyDeployer = _deployKnownZoraFactoryProxy(bytes32(0));

        address gateAdmin = makeAddr("gateAdmin");

        bytes memory upgradeGateDeployCode = type(UpgradeGate).creationCode;

        bytes memory initCall = abi.encodeWithSignature("initialize(address)", gateAdmin);

        bytes32 genericTestDeploySalt = saltWithAddressInFirst20Bytes(deployerAddress, 20);

        bytes32 digest = factoryProxyDeployer.hashedDigestGenericCreation(genericTestDeploySalt, upgradeGateDeployCode, initCall);

        // sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, digest);

        // combine into a single bytes array
        bytes memory signature = abi.encodePacked(r, s, v);

        factoryProxyDeployer.createAndInitGenericContractDeterministic(genericTestDeploySalt, upgradeGateDeployCode, initCall, signature);
    }
}
