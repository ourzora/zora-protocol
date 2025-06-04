// spdx-license-identifier: MIT
pragma solidity ^0.8.20;

import {stdJson, console2} from "forge-std/Script.sol";
import {LibString} from "solady/utils/LibString.sol";
import {CommonBase} from "forge-std/Base.sol";

import {ProxyDeployerConfig, DeterministicContractConfig} from "./Config.sol";
import {ProxyDeployerUtils} from "./ProxyDeployerUtils.sol";
import {DeterministicUUPSProxyDeployer} from "./DeterministicUUPSProxyDeployer.sol";
import {DeterministicDeployerAndCaller} from "./DeterministicDeployerAndCaller.sol";
import {ImmutableCreate2FactoryUtils} from "../utils/ImmutableCreate2FactoryUtils.sol";

interface ISafe {
    function getOwners() external view returns (address[] memory);
}

interface ISymbol {
    function symbol() external view returns (string memory);
}

contract ProxyDeployerScript is CommonBase {
    using stdJson for string;

    function readAddressOrDefaultToZero(string memory json, string memory key) internal view returns (address) {
        string memory keyPrefix = getKeyPrefix(key);

        if (vm.keyExists(json, keyPrefix)) {
            return json.readAddress(keyPrefix);
        } else {
            return address(0);
        }
    }

    // copied from: https://github.com/karmacoma-eth/foundry-playground/blob/main/script/MineSaltScript.sol#L17C1-L36C9
    function mineSalt(
        address deployer,
        bytes32 initCodeHash,
        string memory startsWith,
        address caller
    ) internal returns (bytes32 salt, address expectedAddress) {
        string[] memory args;

        // if there is no caller, we dont need to add the caller to the args
        if (caller == address(0)) args = new string[](8);
        else {
            args = new string[](10);
        }
        args[0] = "cast";
        args[1] = "create2";
        args[2] = "--starts-with";
        args[3] = startsWith;
        args[4] = "--deployer";
        args[5] = LibString.toHexString(deployer);
        args[6] = "--init-code-hash";
        args[7] = LibString.toHexStringNoPrefix(uint256(initCodeHash), 32);
        // if there is a caller, add the caller to the args, enforcing the first 20 bytes will match.
        if (caller != address(0)) {
            args[8] = "--caller";
            args[9] = LibString.toHexString(caller);
        }
        string memory result = string(vm.ffi(args));

        console2.log(result);

        uint256 addressIndex = LibString.indexOf(result, "Address: ");
        string memory addressStr = LibString.slice(result, addressIndex + 9, addressIndex + 9 + 42);
        expectedAddress = vm.parseAddress(addressStr);

        uint256 saltIndex = LibString.indexOf(result, "Salt: ");
        // bytes lengh is 32, + 0x
        // slice is start to end exclusive
        // if start is saltIndex + 6, end should be startIndex + 6 + 64 + 0x (2)
        uint256 startBytes32 = saltIndex + 6;
        string memory saltStr = LibString.slice(result, startBytes32, startBytes32 + 66);

        salt = vm.parseBytes32(saltStr);
    }

    function signDeploymentWithTurnkey(
        DeterministicContractConfig memory config,
        bytes memory init,
        DeterministicDeployerAndCaller deployer
    ) internal returns (bytes memory signature) {
        string[] memory args = new string[](8);

        args[0] = "pnpm";
        args[1] = "exec";
        args[2] = "sign-deploy-and-call-with-turnkey";

        args[3] = vm.toString(block.chainid);

        // salt
        args[4] = vm.toString(config.salt);

        // creation code:
        args[5] = LibString.toHexString(config.creationCode);

        // init
        args[6] = LibString.toHexString(init);

        // deployer address
        args[7] = vm.toString(address(deployer));

        signature = vm.ffi(args);
    }

    function proxyDeployerConfigPath(string memory proxyDeployerName) internal pure returns (string memory) {
        return string.concat("deterministicConfig/", string.concat(proxyDeployerName, ".json"));
    }

    function readProxyDeployerConfig(string memory proxyDeployerName) internal view returns (ProxyDeployerConfig memory config) {
        string memory json = vm.readFile(proxyDeployerConfigPath(proxyDeployerName));

        config.creationCode = json.readBytes(".creationCode");
        config.salt = json.readBytes32(".salt");
        config.deployedAddress = json.readAddress(".deployedAddress");
    }

    function writeProxyDeployerConfig(ProxyDeployerConfig memory config, string memory proxyDeployerName) internal {
        string memory result = "deterministicKey";

        vm.serializeAddress(result, "deployedAddress", config.deployedAddress);
        vm.serializeBytes(result, "creationCode", config.creationCode);
        string memory finalOutput = vm.serializeBytes32(result, "salt", config.salt);

        vm.writeJson(finalOutput, proxyDeployerConfigPath(proxyDeployerName));
    }

    function determinsticConfigJson(DeterministicContractConfig memory config, string memory objectKey) internal returns (string memory result) {
        vm.serializeBytes32(objectKey, "salt", config.salt);
        vm.serializeBytes(objectKey, "creationCode", config.creationCode);
        vm.serializeAddress(objectKey, "deployedAddress", config.deployedAddress);
        vm.serializeString(objectKey, "contractName", config.contractName);
        vm.serializeAddress(objectKey, "deploymentCaller", config.deploymentCaller);
        result = vm.serializeBytes(objectKey, "constructorArgs", config.constructorArgs);
    }

    function saveDeterministicContractConfig(DeterministicContractConfig memory config, string memory contractName) internal {
        string memory configJson = determinsticConfigJson(config, "config");

        vm.writeJson(configJson, proxyDeployerConfigPath(contractName));
    }

    function readDeterministicContractConfig(string memory contractName) internal view returns (DeterministicContractConfig memory config) {
        string memory json = vm.readFile(proxyDeployerConfigPath(contractName));

        config.salt = json.readBytes32(".salt");
        config.deployedAddress = json.readAddress(".deployedAddress");
        config.creationCode = json.readBytes(".creationCode");
        config.contractName = json.readString(".contractName");
        config.constructorArgs = json.readBytes(".constructorArgs");
    }

    function printVerificationCommand(DeterministicContractConfig memory config) internal pure {
        console2.log("to verify:");
        console2.log(
            string.concat(
                "forge verify-contract ",
                LibString.toHexString(config.deployedAddress),
                " ",
                config.contractName,
                " --constructor-args ",
                LibString.toHexString(config.constructorArgs),
                " $(chains {chainName} --deploy)"
            )
        );
    }

    function chainConfigPath() internal view returns (string memory) {
        return string.concat("../shared-contracts/chainConfigs/", vm.toString(block.chainid), ".json");
    }

    function getChainConfigJson() internal view returns (string memory) {
        return vm.readFile(chainConfigPath());
    }

    function getProxyAdmin() internal view virtual returns (address) {
        return validateMultisig(getChainConfigJson().readAddress(".PROXY_ADMIN"));
    }

    function getZoraRecipient() internal view returns (address) {
        return validateMultisig(getChainConfigJson().readAddress(".ZORA_RECIPIENT"));
    }

    function getUniswapSwapRouter() internal view returns (address uniswapSwapRouter) {
        uniswapSwapRouter = getChainConfigJson().readAddress(".UNISWAP_SWAP_ROUTER");

        if (uniswapSwapRouter == address(0)) {
            revert("WETH address not configured");
        }

        if (uniswapSwapRouter.code.length == 0) {
            revert("No code at WETH address");
        }
    }

    function getWeth() internal view returns (address weth) {
        weth = getChainConfigJson().readAddress(".WETH");

        if (weth == address(0)) {
            revert("WETH address not configured");
        }

        if (weth.code.length == 0) {
            revert("No code at WETH address");
        }

        if (keccak256(bytes(ISymbol(weth).symbol())) != keccak256(bytes("WETH"))) {
            revert("WETH does not have symbol WETH. Invalid address configured");
        }
    }

    function getNonFungiblePositionManager() internal view returns (address nonFungiblePositionManager) {
        nonFungiblePositionManager = getChainConfigJson().readAddress(".NONFUNGIBLE_POSITION_MANAGER");

        if (nonFungiblePositionManager.code.length == 0) {
            revert("No code at nonFungiblePositionManager address");
        }

        string memory symbol = ISymbol(nonFungiblePositionManager).symbol();

        if (keccak256(bytes(symbol)) != keccak256(bytes("UNI-V3-POS"))) {
            revert("NonFungiblePositionManager does not have symbol UNI-V3-POS. Invalid address configured");
        }
    }

    function getUniswapV3Factory() internal view returns (address uniswapV3Factory) {
        uniswapV3Factory = getChainConfigJson().readAddress(".UNISWAP_V3_FACTORY");

        if (uniswapV3Factory == address(0)) {
            revert("UniswapV3Factory address not configured");
        }

        if (uniswapV3Factory.code.length == 0) {
            revert("No code at UniswapV3Factory address");
        }
    }

    function getDopplerAirlock() internal view returns (address airlock) {
        airlock = getChainConfigJson().readAddress(".DOPPLER_AIRLOCK");

        if (airlock == address(0)) {
            revert("Airlock address not configured");
        }

        if (airlock.code.length == 0) {
            revert("No code at Airlock address");
        }
    }

    function getUniswapV4PoolManager() internal view returns (address uniswapV4PoolManager) {
        uniswapV4PoolManager = getChainConfigJson().readAddress(".UNISWAP_V4_POOL_MANAGER");

        if (uniswapV4PoolManager == address(0)) {
            revert("UniswapV4PoolManager address not configured");
        }
    }

    function getUniswapV4PositionManager() internal view returns (address uniswapV4PositionManager) {
        uniswapV4PositionManager = getChainConfigJson().readAddress(".UNISWAP_V4_POSITION_MANAGER");

        if (uniswapV4PositionManager == address(0)) {
            revert("UniswapV4PositionManager address not configured");
        }
    }

    function getUniswapPermit2() internal view returns (address permit2) {
        permit2 = getChainConfigJson().readAddress(".UNISWAP_PERMIT2");

        if (permit2 == address(0)) {
            revert("UniswapPermit2 address not configured");
        }
    }

    function getUniswapUniversalRouter() internal view returns (address universalRouter) {
        universalRouter = getChainConfigJson().readAddress(".UNISWAP_UNIVERSAL_ROUTER");

        if (universalRouter == address(0)) {
            revert("UniswapUniversalRouter address not configured");
        }
    }

    function validateMultisig(address multisigAddress) internal view returns (address) {
        if (multisigAddress == address(0)) {
            revert("Cannot be address zero");
        }

        if (multisigAddress.code.length == 0) {
            revert("No code at address");
        }

        if (ISafe(multisigAddress).getOwners().length == 0) {
            revert("No owners on multisig");
        }

        return multisigAddress;
    }

    function generateAndSaveUUPSProxyDeployerConfig() internal {
        bytes32 salt = ImmutableCreate2FactoryUtils.IMMUTABLE_CREATE_2_FRIENDLY_SALT;
        bytes memory creationCode = type(DeterministicUUPSProxyDeployer).creationCode;
        address deterministicAddress = ImmutableCreate2FactoryUtils.immutableCreate2Address(creationCode);

        ProxyDeployerConfig memory config = ProxyDeployerConfig({creationCode: creationCode, salt: salt, deployedAddress: deterministicAddress});

        writeProxyDeployerConfig(config, "uupsProxyDeployer");
    }

    function generateAndSaveDeployerAndCallerConfig() internal {
        bytes32 salt = ImmutableCreate2FactoryUtils.IMMUTABLE_CREATE_2_FRIENDLY_SALT;
        bytes memory creationCode = type(DeterministicDeployerAndCaller).creationCode;
        address deterministicAddress = ImmutableCreate2FactoryUtils.immutableCreate2Address(creationCode);

        ProxyDeployerConfig memory config = ProxyDeployerConfig({creationCode: creationCode, salt: salt, deployedAddress: deterministicAddress});

        writeProxyDeployerConfig(config, "deployerAndCaller");
    }

    function saveProxyDeployerConfig(DeterministicContractConfig memory config, string memory proxyName) internal {
        string memory configJson = determinsticConfigJson(config, "config");

        vm.writeJson(configJson, string.concat(string.concat("deterministicConfig/", proxyName, "/params.json")));
    }

    function createOrGetUUPSProxyDeployer() internal returns (DeterministicUUPSProxyDeployer) {
        ProxyDeployerConfig memory uupsProxyDeployerConfig = readProxyDeployerConfig("uupsProxyDeployer");

        return DeterministicUUPSProxyDeployer(ProxyDeployerUtils.createOrGetProxyDeployer(uupsProxyDeployerConfig));
    }

    function createOrGetDeployerAndCaller() internal returns (DeterministicDeployerAndCaller deployer) {
        ProxyDeployerConfig memory proxyDeployer = readProxyDeployerConfig("deployerAndCaller");

        deployer = DeterministicDeployerAndCaller(ProxyDeployerUtils.createOrGetProxyDeployer(proxyDeployer));

        if (address(deployer) != proxyDeployer.deployedAddress) {
            revert("Mimsatched deployer address");
        }
    }

    /// @notice Return a prefixed key for reading with a ".".
    /// @param key key to prefix
    /// @return prefixed key
    function getKeyPrefix(string memory key) internal pure returns (string memory) {
        return string.concat(".", key);
    }

    function readStringOrDefaultToEmpty(string memory json, string memory key) internal view returns (string memory str) {
        string memory keyPrefix = getKeyPrefix(key);

        if (vm.keyExists(json, keyPrefix)) {
            str = json.readString(keyPrefix);
        } else {
            str = "";
        }
    }

    function readUintOrDefaultToZero(string memory json, string memory key) internal view returns (uint256 num) {
        string memory keyPrefix = getKeyPrefix(key);

        if (vm.keyExists(json, keyPrefix)) {
            num = vm.parseUint(json.readString(keyPrefix));
        }
    }

    // Helper function for reading bytes32 from JSON
    function readBytes32OrDefaultToZero(string memory json, string memory key) internal view returns (bytes32 data) {
        string memory keyPrefix = getKeyPrefix(key);
        if (vm.keyExists(json, keyPrefix)) {
            data = json.readBytes32(keyPrefix);
        }
        // else returns bytes32(0) by default
    }
}
