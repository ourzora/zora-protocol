// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {Zora1155Factory} from "../../src/proxies/Zora1155Factory.sol";
import {ZoraDeployer} from "../../src/deployment/ZoraDeployer.sol";
import {NewFactoryProxyDeployer} from "../../src/deployment/NewFactoryProxyDeployer.sol";
import {ProxyShim} from "../../src/utils/ProxyShim.sol";
import {Deployment, ChainConfig} from "../../src/deployment/DeploymentConfig.sol";
import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

contract NewFactoryProxyDeployerTest is Test {
    function test_proxyCanByDeployedAtDesiredAddress(uint32 nonce) external {
        vm.createSelectFork("zora_goerli", 1252119);
        // ensure nonce is greater than current account's nonce

        // the values in this test can be determined by running the script GetDeterminsticParam.s.sol,
        // and copying the output values here.
        address deployerAddress = 0xf69fEc6d858c77e969509843852178bd24CAd2B6;
        bytes32 newFactoryProxyDeployerCreationSalt = bytes32(0xf69fec6d858c77e969509843852178bd24cad2b6000000000000000000000000);
        bytes32 proxyShimSalt = bytes32(0x89d6b41491ad0d71482f348ec72c10d6136989b1538d35513f4de605f2870242);
        bytes32 factoryProxySalt = bytes32(0x75e385b83ee33131a9819dae53d14965755511550cd440e95966440231121260);

        address expectedFactoryDeployeAddress = 0x29240D422C821A871A16CcAB88abeb2889180146;
        address expectedAddress = 0x7777777f9F0980A03C5a14dc81A17D0391b5b7D5;

        // now we can create the implementation, pointing it to the expected determinstic address:
        address mintFeeRecipient = makeAddr("mintFeeRecipient");
        address factoryOwner = makeAddr("factorOwner");
        address protocolRewards = makeAddr("protocolRewards");

        (address determinsticFactoryDeployerAddress, address determinsticFactoryProxyAddress) = ZoraDeployer.determinsticFactoryDeployerAndFactoryProxyAddress({
            deployerAddress: deployerAddress,
            factoryDeloyerSalt: newFactoryProxyDeployerCreationSalt,
            proxyShimSalt: proxyShimSalt,
            factoryProxySalt: factoryProxySalt
        });

        assertEq(determinsticFactoryDeployerAddress, expectedFactoryDeployeAddress, "determinstic factory deployer address wrong");
        assertEq(determinsticFactoryProxyAddress, expectedAddress, "determinstic factory proxy address wrong");

        // 1. Create implementation contracts based on determinstic factory proxy address

        // create 1155 and factory impl, we can know the determinstic factor proxy address ahead of time:
        (address factoryImplAddress, ) = ZoraDeployer.deployNew1155AndFactoryImpl({
            factoryProxyAddress: determinsticFactoryProxyAddress,
            mintFeeRecipient: mintFeeRecipient,
            protocolRewards: protocolRewards,
            merkleMinter: IMinter1155(address(0)),
            redeemMinterFactory: IMinter1155(address(0)),
            fixedPriceMinter: IMinter1155(address(0))
        });

        vm.assume(nonce > vm.getNonce(deployerAddress));
        // we set the nonce to a random value, to prove this doesn't affect the determinstic addrss
        vm.setNonce(deployerAddress, nonce);

        bytes memory newFactoryProxyDeployerInitCode = abi.encodePacked(type(NewFactoryProxyDeployer).creationCode, abi.encode(deployerAddress));

        // 2. Create factory deployer at determinstic address

        // create new factory deployer using ImmutableCreate2Factory
        vm.prank(deployerAddress);
        address newFactoryProxyDeployerAddress = ZoraDeployer.IMMUTABLE_CREATE2_FACTORY.safeCreate2(
            newFactoryProxyDeployerCreationSalt,
            newFactoryProxyDeployerInitCode
        );

        assertEq(newFactoryProxyDeployerAddress, determinsticFactoryDeployerAddress, "factory deployer address wrong");

        // create factory proxy at determinstic address:
        NewFactoryProxyDeployer factoryProxyDeployer = NewFactoryProxyDeployer(newFactoryProxyDeployerAddress);

        // try to create and initialize factory proxy as another account, it should revert, as only original deployer should be
        // able to call this:
        vm.prank(makeAddr("other"));
        vm.expectRevert();
        factoryProxyDeployer.createAndInitializeNewFactoryProxyDeterminstic(
            proxyShimSalt,
            factoryProxySalt,
            determinsticFactoryProxyAddress,
            factoryImplAddress,
            factoryOwner
        );

        // now do it as original deployer, it should succeed:
        vm.prank(deployerAddress);
        address factoryProxyAddress = factoryProxyDeployer.createAndInitializeNewFactoryProxyDeterminstic(
            proxyShimSalt,
            factoryProxySalt,
            determinsticFactoryProxyAddress,
            factoryImplAddress,
            factoryOwner
        );

        // we know this salt from a script we ran that will generated
        // create factory proxy, using determinstic address and known salt to get proper expected address:
        assertEq(factoryProxyAddress, expectedAddress, "factory proxy address wrong");
    }
}
