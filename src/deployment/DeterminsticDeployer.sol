// spdx-license-identifier: mit
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
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
import {LibString} from "solady/utils/LibString.sol";

struct DeterminsticParams {
    bytes proxyDeployerCreationCode;
    bytes proxyCreationCode;
    address deployerAddress;
    address proxyDeployerAddress;
    bytes32 proxyDeployerSalt;
    bytes32 proxyShimSalt;
    bytes32 proxySalt;
    address determinsticProxyAddress;
}

contract DeterminsticDeployer is Script {
    using stdJson for string;

    // copied from: https://github.com/karmacoma-eth/foundry-playground/blob/main/script/MineSaltScript.sol#L17C1-L36C9
    function mineSalt(address deployer, bytes32 initCodeHash, string memory startsWith) internal returns (bytes32 salt, address expectedAddress) {
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

    function serializeAndSaveOutput(DeterminsticParams memory params) internal {
        string memory result = "determinsitc_key";

        vm.serializeBytes(result, "proxyDeployerCreationCode", params.proxyDeployerCreationCode);
        vm.serializeBytes(result, "proxyCreationCode", params.proxyCreationCode);
        vm.serializeAddress(result, "deployerAddress", params.deployerAddress);
        vm.serializeAddress(result, "proxyDeployerAddress", params.proxyDeployerAddress);
        vm.serializeBytes32(result, "proxyDeployerSalt", params.proxyDeployerSalt);
        vm.serializeBytes32(result, "proxyShimSalt", params.proxyShimSalt);
        vm.serializeBytes32(result, "proxySalt", params.proxySalt);

        string memory finalOutput = vm.serializeAddress(result, "determinsticProxyAddress", params.determinsticProxyAddress);

        console2.log(finalOutput);

        vm.writeJson(finalOutput, "determinsticConfig/factoryProxy/params.json");
    }

    function readDeterminsticParams(string memory proxyName, uint256 chain) internal returns (DeterminsticParams memory params, bytes memory signature) {
        string memory root = vm.projectRoot();
        string memory folder = string.concat(string.concat(root, "/determinsticConfig/"), proxyName);
        string memory deployConfig = vm.readFile(string.concat(folder, "/params.json"));
        string memory signatures = vm.readFile(string.concat(folder, "/signatures.json"));

        params = DeterminsticParams({
            proxyDeployerCreationCode: deployConfig.readBytes(".proxyDeployerCreationCode"),
            proxyCreationCode: deployConfig.readBytes(".proxyCreationCode"),
            deployerAddress: deployConfig.readAddress(".deployerAddress"),
            proxyDeployerAddress: deployConfig.readAddress(".proxyDeployerAddress"),
            proxyDeployerSalt: deployConfig.readBytes32(".proxyDeployerSalt"),
            proxyShimSalt: deployConfig.readBytes32(".proxyShimSalt"),
            proxySalt: deployConfig.readBytes32(".proxySalt"),
            determinsticProxyAddress: deployConfig.readAddress(".determinsticProxyAddress")
        });

        signature = signatures.readBytes(string.concat(".", string.concat(vm.toString(chain))));
    }
}
