// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {Zora1155Factory} from "../../src/proxies/Zora1155Factory.sol";
import {ZoraDeployerUtils} from "../../src/deployment/ZoraDeployerUtils.sol";
import {DeterministicProxyDeployer} from "../../src/deployment/DeterministicProxyDeployer.sol";
import {ProxyShim} from "../../src/utils/ProxyShim.sol";
import {UpgradeGate} from "../../src/upgrades/UpgradeGate.sol";
import {Deployment, ChainConfig} from "../../src/deployment/DeploymentConfig.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract DeterministicProxyDeployerTest is Test {
    using stdJson for string;

    // the values in this test can be determined by running the script GetDeterministicParam.s.sol,
    // and copying the output values here.
    bytes32 DeterministicProxyDeployerCreationSalt = bytes32(0x0000000000000000000000000000000000000000668d7f9eb18e35000dbaba0e);
    bytes32 proxyShimSalt = bytes32(0xf69fec6d858c77e969509843852178bd24cad2b6000000000000000000000000);
    bytes32 factoryProxySalt = bytes32(0xe06d3223ede55655f68ce124bc16c9c311a20c31806ca2b04056664a574e2f1d);

    function setUp() public {
        string memory deployConfig = vm.readFile(string.concat(string.concat(vm.projectRoot(), "/deterministicConfig/factoryProxy", "/params.json")));

        DeterministicProxyDeployerCreationSalt = deployConfig.readBytes32(".proxyDeployerSalt");
        proxyShimSalt = deployConfig.readBytes32(".proxyShimSalt");
        factoryProxySalt = deployConfig.readBytes32(".proxyDeployerSalt");
    }

    function _deployKnownZoraFactoryProxy() internal returns (DeterministicProxyDeployer factoryProxyDeployer) {
        bytes memory DeterministicProxyDeployerInitCode = type(DeterministicProxyDeployer).creationCode;

        address computedFactoryDeployerAddress = ZoraDeployerUtils.IMMUTABLE_CREATE2_FACTORY.findCreate2Address(
            DeterministicProxyDeployerCreationSalt,
            DeterministicProxyDeployerInitCode
        );

        address expectedFactoryDeployerAddress = 0x9868a3FFe92C44c4Ce1db8033C6f55a674D511D8;
        assertEq(computedFactoryDeployerAddress, expectedFactoryDeployerAddress, "deterministic factory deployer address wrong");

        address computedFactoryProxyAddress = ZoraDeployerUtils.deterministicFactoryProxyAddress({
            proxyShimSalt: proxyShimSalt,
            factoryProxySalt: factoryProxySalt,
            proxyDeployerAddress: computedFactoryDeployerAddress
        });

        address expectedFactoryProxyAddress = 0x77777718F04F2f9d9082a5AC853cBA682b19fB48;
        assertEq(computedFactoryProxyAddress, expectedFactoryProxyAddress, "deterministic factory proxy address wrong");

        // create new factory deployer using ImmutableCreate2Factory
        address DeterministicProxyDeployerAddress = ZoraDeployerUtils.IMMUTABLE_CREATE2_FACTORY.safeCreate2(
            DeterministicProxyDeployerCreationSalt,
            DeterministicProxyDeployerInitCode
        );

        assertEq(DeterministicProxyDeployerAddress, computedFactoryDeployerAddress, "factory deployer address wrong");

        assertEq(computedFactoryDeployerAddress, address(0x77777718F04F2f9d9082a5AC853cBA682b19fB48));

        // create factory proxy at deterministic address:
        factoryProxyDeployer = DeterministicProxyDeployer(DeterministicProxyDeployerAddress);
    }

    function test_proxyCanByDeployedAtDesiredAddress(uint32 nonce) external {
        vm.createSelectFork("zora_goerli", 1252119);
        // ensure nonce is greater than current account's nonce

        (address deployerAddress, uint256 deployerPrivateKey) = makeAddrAndKey("deployer");

        // address expectedFactoryDeployerAddress = 0x9868a3FFe92C44c4Ce1db8033C6f55a674D511D8;
        address expectedFactoryProxyAddress = 0x77777718F04F2f9d9082a5AC853cBA682b19fB48;

        // now we can create the implementation, pointing it to the expected deterministic address:
        address mintFeeRecipient = makeAddr("mintFeeRecipient");
        address factoryOwner = makeAddr("factorOwner");
        address protocolRewards = makeAddr("protocolRewards");

        // 1. Create implementation contracts based on deterministic factory proxy address

        // create 1155 and factory impl, we can know the deterministic factor proxy address ahead of time:
        (address factoryImplAddress, ) = ZoraDeployerUtils.deployNew1155AndFactoryImpl({
            factoryProxyAddress: expectedFactoryProxyAddress,
            mintFeeRecipient: mintFeeRecipient,
            protocolRewards: protocolRewards,
            merkleMinter: IMinter1155(address(0)),
            redeemMinterFactory: IMinter1155(address(0)),
            fixedPriceMinter: IMinter1155(address(0))
        });

        vm.assume(nonce > vm.getNonce(deployerAddress));
        // we set the nonce to a random value, to prove this doesn't affect the deterministic addrss
        vm.setNonce(deployerAddress, nonce);

        // 2. Create factory deployer at deterministic address
        DeterministicProxyDeployer factoryProxyDeployer = _deployKnownZoraFactoryProxy();

        // // try to create and initialize factory proxy as another account, it should revert, as only original deployer should be
        // // able to call this:
        // vm.prank(makeAddr("other"));
        // vm.expectRevert();
        // factoryProxyDeployer.createAndInitializeNewFactoryProxyDeterministic(
        //     proxyShimSalt,
        //     factoryProxySalt,
        //     deterministicFactoryProxyAddress,
        //     factoryImplAddress,
        //     factoryOwner
        // );

        bytes memory factoryProxyCreationCode = type(Zora1155Factory).creationCode;

        bytes32 digest = factoryProxyDeployer.hashedDigestFactoryProxy(
            proxyShimSalt,
            factoryProxySalt,
            factoryProxyCreationCode,
            factoryImplAddress,
            factoryOwner
        );

        // sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, digest);

        // combine into a single bytes array
        bytes memory signature = abi.encodePacked(r, s, v);

        // now do it as original deployer, it should succeed:
        address factoryProxyAddress = factoryProxyDeployer.createFactoryProxyDeterministic(
            proxyShimSalt,
            factoryProxySalt,
            factoryProxyCreationCode,
            expectedFactoryProxyAddress,
            factoryImplAddress,
            factoryOwner,
            signature
        );

        // we know this salt from a script we ran that will generated
        // create factory proxy, using deterministic address and known salt to get proper expected address:
        assertEq(factoryProxyAddress, expectedFactoryProxyAddress, "factory proxy address wrong");
    }

    function test_genericContractCanByDeployedAtDesiredAddress(uint32 nonce) external {
        vm.createSelectFork("zora_goerli", 1252119);

        (address deployerAddress, uint256 deployerPrivateKey) = makeAddrAndKey("deployer");

        vm.assume(nonce > vm.getNonce(deployerAddress));
        // we set the nonce to a random value, to prove this doesn't affect the deterministic addrss
        vm.setNonce(deployerAddress, nonce);

        DeterministicProxyDeployer factoryProxyDeployer = _deployKnownZoraFactoryProxy();

        address gateAdmin = makeAddr("gateAdmin");

        bytes memory upgradeGateDeployCode = type(UpgradeGate).creationCode;

        bytes memory initCall = abi.encodeWithSignature("initialize(address)", gateAdmin);

        bytes32 genericTestDeploySalt = bytes32(0x0000000000000000000000000000000000000000baaaaaacafeaaaaaacafef00) &
            bytes32(uint256(uint160(address(deployerAddress))) << 96);

        bytes32 digest = factoryProxyDeployer.hashedDigestGenericCreation(genericTestDeploySalt, upgradeGateDeployCode, initCall);

        // sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, digest);

        // combine into a single bytes array
        bytes memory signature = abi.encodePacked(r, s, v);

        factoryProxyDeployer.createAndInitGenericContractDeterministic(genericTestDeploySalt, upgradeGateDeployCode, initCall, signature);
    }
}
