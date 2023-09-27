// spdx-license-identifier: mit
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {ZoraDeployerBase} from "./ZoraDeployerBase.sol";
import {Zora1155Factory} from "../src/proxies/Zora1155Factory.sol";
import {ProxyShim} from "../src/utils/ProxyShim.sol";
import {LibString} from "solady/utils/LibString.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ZoraDeployer} from "../src/deployment/ZoraDeployer.sol";
import {NewFactoryProxyDeployer} from "../src/deployment/NewFactoryProxyDeployer.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title Gets parameters for determinstically deploying a new factory proxy at an address starting with 0x777777, regardless of the chain.
/// Example usage: DEPLOYER=0xf69fEc6d858c77e969509843852178bd24CAd2B6 forge script script/GetDeterminsticParam.s.sol --rpc-url https://testnet.rpc.zora.energy --ffi
/// @author
/// @notice
contract GetDeterminsticParam is ZoraDeployerBase {
    // copied from: https://github.com/karmacoma-eth/foundry-playground/blob/main/script/MineSaltScript.sol#L17C1-L36C9
    function mineSalt(address deployer, bytes32 initCodeHash, string memory startsWith) public returns (bytes32 salt, address expectedAddress) {
        string[] memory args = new string[](8);
        args[0] = "cast";
        args[1] = "create2";
        args[2] = "--starts-with";
        args[3] = startsWith;
        args[4] = "--deployer";
        args[5] = LibString.toHexString(deployer);
        args[6] = "--init-code-hash";
        args[7] = LibString.toHexStringNoPrefix(uint256(initCodeHash), 32);
        string memory result = string(vm.ffi(args));

        uint256 addressIndex = LibString.indexOf(result, "Address: ");
        string memory addressStr = LibString.slice(result, addressIndex + 9, addressIndex + 9 + 42);
        expectedAddress = vm.parseAddress(addressStr);

        uint256 saltIndex = LibString.indexOf(result, "Salt: ");
        string memory saltStr = LibString.slice(result, saltIndex + 6, bytes(result).length);

        salt = bytes32(vm.parseUint(saltStr));
    }

    function saltWithAddressInFirst20Bytes(address addressToMakeSaltWith) internal pure returns (bytes32) {
        uint256 shifted = uint256(uint160(address(addressToMakeSaltWith))) << 96;

        return bytes32(shifted);
    }

    function getDeterminsticParams(
        address deployerAddress
    )
        internal
        returns (
            bytes32 newFactoryProxyDeployerSalt,
            address factoryDeployerAddress,
            bytes32 proxyShimSalt,
            bytes32 factoryProxySalt,
            address determinsticFactoryProxyAddress
        )
    {
        // 1. Get salt with first bytes that match address, and resulting determinsitic factory proxy deployer address

        // replace first 20 characters of salt with deployer address, so that the salt can be used with
        // ImmutableCreate2Factory.safeCreate2 when called by this deployer's account:
        newFactoryProxyDeployerSalt = ZoraDeployer.FACTORY_DEPLOYER_DEPLOYMENT_SALT;

        bytes memory newFactoryProxyDeployerInitCode = type(NewFactoryProxyDeployer).creationCode;

        // we can know determinstically what the address of the new factory proxy deployer will be, given it's deployed from with the salt and init code,
        // from the ImmutableCreate2Factory
        factoryDeployerAddress = ZoraDeployer.determinsticFactoryDeployerAddress();

        console2.log("expected factory deployer address:", factoryDeployerAddress);

        // 2. Get random proxy shim salt, and resulting determinstic address

        // Proxy shim will be initialized with the factory deployer address as the owner, allowing only the factory deployer to upgrade the proxy,
        // to the eventual factory implementation
        bytes memory proxyShimInitCode = abi.encodePacked(type(ProxyShim).creationCode, abi.encode(factoryDeployerAddress));

        // create any arbitrary salt for proxy shim (this can be anything, we just care about the resulting address)
        proxyShimSalt = saltWithAddressInFirst20Bytes(deployerAddress);

        // now get determinstic proxy shim address based on salt, deployer address, which will be NewFactoryProxyDeployer address and init code
        address proxyShimAddress = Create2.computeAddress(proxyShimSalt, keccak256(proxyShimInitCode), factoryDeployerAddress);

        console2.log("proxy shim address:");
        console2.log(proxyShimAddress);

        // 3. Mine for a salt that can be used to determinstically create the factory proxy, given the proxy shim address, which is passed as the
        // constructor argument, and the deployer, which is the new factory proxy deployer, which we know the address of determinstically

        bytes memory factoryProxyInitCode = abi.encodePacked(type(Zora1155Factory).creationCode, abi.encode(proxyShimAddress, ""));
        bytes32 creationCodeHash = keccak256(factoryProxyInitCode);

        console.log("init code hash: ", LibString.toHexStringNoPrefix(uint256(creationCodeHash), 32));

        (factoryProxySalt, determinsticFactoryProxyAddress) = mineSalt(factoryDeployerAddress, creationCodeHash, "777777");
    }

    function run()
        public
        returns (
            bytes memory newFactoryDeployerCreationCode,
            address deployerAddress,
            address determinsticDeployerAddress,
            bytes32 newFactoryProxyDeployerSalt,
            bytes32 proxyShimSalt,
            bytes32 factoryProxySalt,
            address determinsticFactoryProxyAddress
        )
    {
        deployerAddress = 0x4F9991C82C76aE04CC39f23aB909AA919886ba12;
        // (deployerAddress, deployerPrivateKey) = makeAddrAndKey("deployer");
        // deployerAddress = vm.envAddress("DEPLOYER");

        (newFactoryProxyDeployerSalt, determinsticDeployerAddress, proxyShimSalt, factoryProxySalt, determinsticFactoryProxyAddress) = getDeterminsticParams(
            deployerAddress
        );

        newFactoryDeployerCreationCode = type(NewFactoryProxyDeployer).creationCode;

        // extract results
        console2.log("deployer address: ", deployerAddress);
        // only used for test purposes
        // console2.log("deployer pivate key", deployerPrivateKey);
        console2.log("new factory proxy deployer salt:", vm.toString(newFactoryProxyDeployerSalt));
        console2.log("proxy shim bytes32 salt:", vm.toString(proxyShimSalt));
        console2.log("factory proxy bytes32 salt: ", vm.toString(factoryProxySalt));
        console2.log("expected address: ", determinsticFactoryProxyAddress);
    }
}
