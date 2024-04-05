// SPDX-License-Identifier: MIT

import "forge-std/Test.sol";
import {IZoraCreator1155PremintExecutorV2} from "@zoralabs/shared-contracts/interfaces/IZoraCreator1155PremintExecutorV2.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";
import {DeterministicUUPSProxyDeployer} from "../src/DeterministicUUPSProxyDeployer.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ZoraMintsManager} from "@zoralabs/mints-contracts/src/ZoraMintsManager.sol";
import {ZoraMintsManagerImpl} from "@zoralabs/mints-contracts/src/ZoraMintsManagerImpl.sol";
import {ZoraMints1155} from "@zoralabs/mints-contracts/src/ZoraMints1155.sol";
import {ProxyDeployerUtils} from "../src/ProxyDeployerUtils.sol";
import {IZoraMintsManager} from "@zoralabs/mints-contracts/src/interfaces/IZoraMintsManager.sol";

contract DeterministicUUPSProxyDeployerDeployerTest is Test {
    using stdJson for string;

    DeterministicUUPSProxyDeployer proxyDeployer;

    IZoraCreator1155PremintExecutorV2 preminter;

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

        // now create the mints proxy:
        proxyDeployer.safeCreate2AndUpgradeToAndCall(
            proxySalt,
            proxyCode,
            initialImplementationAddress,
            initialImplementationCall,
            expectedTransparentProxyAddress
        );

        transparentProxy = UUPSUpgradeable(expectedTransparentProxyAddress);
    }

    function _deployMintsProxy(
        address initialImplementationAddress,
        bytes32 proxySalt,
        bytes32 mints1155Salt,
        address proxyAdmin,
        address initialMintsOwner,
        uint256 initialEthTokenId,
        uint256 initialEthPrice
    ) internal returns (UUPSUpgradeable proxy) {
        bytes memory proxyCode = type(ZoraMintsManager).creationCode;

        // encode initialize(address initialOwner, uint256 initialEthTokenId, uint256 initialEthTokenPrice)
        bytes memory initialImplementationCall = ProxyDeployerUtils.mintsManagerInitializeCall(
            initialMintsOwner,
            ProxyDeployerUtils.mints1155CreationCode(),
            mints1155Salt,
            initialEthTokenId,
            initialEthPrice
        );

        return _deployProxy(proxyCode, proxySalt, initialImplementationAddress, initialImplementationCall);
    }

    function test_transparentProxyCanBeDeployedAtDesiredAddress() external {
        address deployerAddress = makeAddr("deployer");

        bytes32 transparentProxySalt = ImmutableCreate2FactoryUtils.saltWithAddressInFirst20Bytes(deployerAddress, 10);

        address initialImplementationAddress = address(new ZoraMintsManagerImpl(preminter));

        // build initialize call, that will be called upon upgrade
        address initialMintsOwner = makeAddr("mintsOwner");
        uint256 initialEthTokenId = 1;
        uint256 initialEthPrice = 0.25 ether;

        // this address will become the upgrade admin of the proxy contract
        address proxyAdmin = makeAddr("proxyAdmin");

        bytes32 mints1155Salt;

        vm.startPrank(deployerAddress);
        UUPSUpgradeable proxy = _deployMintsProxy(
            initialImplementationAddress,
            transparentProxySalt,
            mints1155Salt,
            proxyAdmin,
            initialMintsOwner,
            initialEthTokenId,
            initialEthPrice
        );
        vm.stopPrank();

        IZoraMintsManager mints = IZoraMintsManager(address(proxy));

        assertEq(ZoraMintsManagerImpl(address(mints)).owner(), initialMintsOwner);
        assertEq(mints.mintableEthToken(), initialEthTokenId);
        assertEq(mints.getEthPrice(), initialEthPrice);
    }

    function test_createdProxy_canOnlyBeUpgradeByProxyAdmin() external {
        address deployerAddress = makeAddr("deployer");

        bytes32 transparentProxySalt = ImmutableCreate2FactoryUtils.saltWithAddressInFirst20Bytes(deployerAddress, 10);

        address initialImplementationAddress = address(new ZoraMintsManagerImpl(preminter));

        // build initialize call, that will be called upon upgrade
        address mintsOwner = makeAddr("mintsOwner");
        uint256 initialEthTokenId = 1;
        uint256 initialEthPrice = 0.25 ether;

        // this address will become the upgrade admin of the proxy contract
        address proxyAdmin = makeAddr("proxyAdmin");

        bytes32 mints1155Salt;

        vm.startPrank(deployerAddress);
        UUPSUpgradeable proxy = _deployMintsProxy(
            initialImplementationAddress,
            transparentProxySalt,
            mints1155Salt,
            proxyAdmin,
            mintsOwner,
            initialEthTokenId,
            initialEthPrice
        );
        vm.stopPrank();

        address newImpl = address(new ZoraMintsManagerImpl(preminter));

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
        proxyAdmin = mintsOwner;
        vm.prank(proxyAdmin);
        proxy.upgradeToAndCall(newImpl, "");

        assertEq(ZoraMintsManagerImpl(address(proxy)).implementation(), newImpl);
    }

    function test_revertsWhen_addressDoesntMatchSalt() external {
        address deployerAddress = makeAddr("deployer");

        address badDeployer = makeAddr("badDeployer");

        bytes32 transparentProxySalt = ImmutableCreate2FactoryUtils.saltWithAddressInFirst20Bytes(deployerAddress, 10);

        bytes32 mints1155Salt = bytes32(0);

        address initialImplementationAddress = address(new ZoraMintsManagerImpl(preminter));

        // build initialize call, that will be called upon upgrade
        address initialMintsOwner = makeAddr("mintsOwner");
        uint256 initialEthTokenId = 1;
        uint256 initialEthPrice = 0.25 ether;

        // this address will become the upgrade admin of the proxy contract
        // address proxyAdmin = makeAddr("proxyAdmin");

        bytes memory transparentProxyCode = type(ZoraMintsManager).creationCode;

        // encode initialize(address initialOwner, uint256 initialEthTokenId, uint256 initialEthTokenPrice)
        bytes memory initialImplementationCall = ProxyDeployerUtils.mintsManagerInitializeCall(
            initialMintsOwner,
            ProxyDeployerUtils.mints1155CreationCode(),
            mints1155Salt,
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

    function signAndMakeBytes(bytes32 digest, uint256 privateKey) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        // combine into a single bytes array
        return abi.encodePacked(r, s, v);
    }
}
