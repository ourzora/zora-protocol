// SPDX-License-Identifier: MIT

import "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";
import {DeterministicUUPSProxyDeployer} from "../src/DeterministicUUPSProxyDeployer.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ZoraSparksManager} from "@zoralabs/sparks-contracts/src/ZoraSparksManager.sol";
import {ZoraSparksManagerImpl} from "@zoralabs/sparks-contracts/src/ZoraSparksManagerImpl.sol";
import {ZoraSparks1155} from "@zoralabs/sparks-contracts/src/ZoraSparks1155.sol";
import {ProxyDeployerUtils} from "../src/ProxyDeployerUtils.sol";
import {IZoraSparksManager} from "@zoralabs/sparks-contracts/src/interfaces/IZoraSparksManager.sol";

contract DeterministicUUPSProxyDeployerDeployerTest is Test {
    using stdJson for string;

    DeterministicUUPSProxyDeployer proxyDeployer;

    function setUp() external {
        vm.createSelectFork("zora", 9718296);
        proxyDeployer = _deployOrGetDeterministicProxyDeployer(bytes32(0x0000000000000000000000000000000000000000000000000000000000000000));
    }

    // the values in this test can be determined by running the script GetDeterministicParam.s.sol,
    // and copying the output values here.
    function _deployOrGetDeterministicProxyDeployer(bytes32 salt) internal returns (DeterministicUUPSProxyDeployer) {
        return DeterministicUUPSProxyDeployer(ImmutableCreate2FactoryUtils.safeCreate2OrGetExisting(salt, type(DeterministicUUPSProxyDeployer).creationCode));
    }

    function _deployProxy(
        bytes memory proxyCode,
        bytes32 proxySalt,
        address initialImplementationAddress,
        bytes memory initialImplementationCall
    ) internal returns (UUPSUpgradeable transparentProxy) {
        address expectedTransparentProxyAddress = proxyDeployer.expectedProxyAddress(proxySalt, proxyCode);

        // now create the sparks proxy:
        proxyDeployer.safeCreate2AndUpgradeToAndCall(
            proxySalt,
            proxyCode,
            initialImplementationAddress,
            initialImplementationCall,
            expectedTransparentProxyAddress
        );

        transparentProxy = UUPSUpgradeable(expectedTransparentProxyAddress);
    }

    function _deploySparksProxy(
        address initialImplementationAddress,
        bytes32 proxySalt,
        bytes32 sparks1155Salt,
        address proxyAdmin,
        address initialSparksOwner,
        uint256 initialEthTokenId,
        uint256 initialEthPrice
    ) internal returns (UUPSUpgradeable proxy) {
        bytes memory proxyCode = type(ZoraSparksManager).creationCode;

        // encode initialize(address initialOwner, uint256 initialEthTokenId, uint256 initialEthTokenPrice)
        bytes memory initialImplementationCall = ProxyDeployerUtils.sparksManagerInitializeCall(
            initialSparksOwner,
            ProxyDeployerUtils.sparks1155CreationCode(),
            sparks1155Salt,
            initialEthTokenId,
            initialEthPrice
        );

        return _deployProxy(proxyCode, proxySalt, initialImplementationAddress, initialImplementationCall);
    }

    function test_transparentProxyCanBeDeployedAtDesiredAddress() external {
        address deployerAddress = makeAddr("deployer");

        bytes32 transparentProxySalt = ImmutableCreate2FactoryUtils.saltWithAddressInFirst20Bytes(deployerAddress, 10);

        address initialImplementationAddress = address(new ZoraSparksManagerImpl());

        // build initialize call, that will be called upon upgrade
        address initialSparksOwner = makeAddr("sparksOwner");
        uint256 initialEthTokenId = 1;
        uint256 initialEthPrice = 0.25 ether;

        // this address will become the upgrade admin of the proxy contract
        address proxyAdmin = makeAddr("proxyAdmin");

        bytes32 sparks1155Salt;

        vm.startPrank(deployerAddress);
        UUPSUpgradeable proxy = _deploySparksProxy(
            initialImplementationAddress,
            transparentProxySalt,
            sparks1155Salt,
            proxyAdmin,
            initialSparksOwner,
            initialEthTokenId,
            initialEthPrice
        );
        vm.stopPrank();

        IZoraSparksManager sparks = IZoraSparksManager(address(proxy));

        assertEq(ZoraSparksManagerImpl(address(sparks)).owner(), initialSparksOwner);
        assertEq(sparks.zoraSparks1155().tokenPrice(initialEthTokenId), initialEthPrice);
    }

    function test_createdProxy_canOnlyBeUpgradeByProxyAdmin() external {
        address deployerAddress = makeAddr("deployer");

        bytes32 transparentProxySalt = ImmutableCreate2FactoryUtils.saltWithAddressInFirst20Bytes(deployerAddress, 10);

        address initialImplementationAddress = address(new ZoraSparksManagerImpl());

        // build initialize call, that will be called upon upgrade
        address sparksOwner = makeAddr("sparksOwner");
        uint256 initialEthTokenId = 1;
        uint256 initialEthPrice = 0.25 ether;

        // this address will become the upgrade admin of the proxy contract
        address proxyAdmin = makeAddr("proxyAdmin");

        bytes32 sparks1155Salt;

        vm.startPrank(deployerAddress);
        UUPSUpgradeable proxy = _deploySparksProxy(
            initialImplementationAddress,
            transparentProxySalt,
            sparks1155Salt,
            proxyAdmin,
            sparksOwner,
            initialEthTokenId,
            initialEthPrice
        );
        vm.stopPrank();

        address newImpl = address(new ZoraSparksManagerImpl());

        // deployer owner cannot upgrade the contract
        vm.prank(deployerAddress);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, deployerAddress));
        proxy.upgradeToAndCall(newImpl, "");

        // proxy deployer contract cannot upgrade the contract
        vm.prank(address(proxyDeployer));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(proxyDeployer)));
        proxy.upgradeToAndCall(newImpl, "");

        // proxy admin can upgrade the contract
        // for now they are the same
        proxyAdmin = sparksOwner;
        vm.prank(proxyAdmin);
        proxy.upgradeToAndCall(newImpl, "");

        assertEq(ZoraSparksManagerImpl(address(proxy)).implementation(), newImpl);
    }

    function test_revertsWhen_addressDoesntMatchSalt() external {
        address deployerAddress = makeAddr("deployer");

        address badDeployer = makeAddr("badDeployer");

        bytes32 transparentProxySalt = ImmutableCreate2FactoryUtils.saltWithAddressInFirst20Bytes(deployerAddress, 10);

        bytes32 sparks1155Salt = bytes32(0);

        address initialImplementationAddress = address(new ZoraSparksManagerImpl());

        // build initialize call, that will be called upon upgrade
        address initialSparksOwner = makeAddr("sparksOwner");
        uint256 initialEthTokenId = 1;
        uint256 initialEthPrice = 0.25 ether;

        // this address will become the upgrade admin of the proxy contract
        // address proxyAdmin = makeAddr("proxyAdmin");

        bytes memory transparentProxyCode = type(ZoraSparksManager).creationCode;

        // encode initialize(address initialOwner, uint256 initialEthTokenId, uint256 initialEthTokenPrice)
        bytes memory initialImplementationCall = ProxyDeployerUtils.sparksManagerInitializeCall(
            initialSparksOwner,
            ProxyDeployerUtils.sparks1155CreationCode(),
            sparks1155Salt,
            initialEthTokenId,
            initialEthPrice
        );

        address expectedProxyAddress = proxyDeployer.expectedProxyAddress(transparentProxySalt, transparentProxyCode);

        vm.startPrank(badDeployer);
        vm.expectRevert(abi.encodeWithSelector(DeterministicUUPSProxyDeployer.InvalidSalt.selector, badDeployer, transparentProxySalt));

        proxyDeployer.safeCreate2AndUpgradeToAndCall(
            transparentProxySalt,
            transparentProxyCode,
            initialImplementationAddress,
            initialImplementationCall,
            expectedProxyAddress
        );
    }
}
