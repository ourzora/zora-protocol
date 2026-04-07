// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";
import {ProxyDeployerScript, DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {LibString} from "solady/utils/LibString.sol";
import {ZoraLimitOrderBook} from "@zoralabs/limit-orders/ZoraLimitOrderBook.sol";
import {SwapWithLimitOrders} from "@zoralabs/limit-orders/router/SwapWithLimitOrders.sol";
import "../src/deployment/CoinsDeployerBase.sol";

/// @title GenerateLimitOrderParams
/// @notice Mines deterministic salts for limit order contracts to generate addresses starting with "7777777"
/// @dev This script uses FFI to mine salts using `cast create2`. Run with --ffi flag.
contract GenerateLimitOrderParams is CoinsDeployerBase {
    function mineSaltWithCaller(
        address deployer,
        bytes32 initCodeHash,
        string memory startsWith,
        address caller
    ) internal returns (bytes32 salt, address expectedAddress) {
        bytes memory result = _callCast(deployer, initCodeHash, startsWith, caller);
        (salt, expectedAddress) = _parseResult(result);
    }

    function _callCast(address deployer, bytes32 initCodeHash, string memory startsWith, address caller) private returns (bytes memory) {
        string[] memory args;

        // If there is a caller, add it to the args to enforce first 20 bytes will match
        if (caller == address(0)) {
            args = new string[](8);
        } else {
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

        if (caller != address(0)) {
            args[8] = "--caller";
            args[9] = LibString.toHexString(caller);
        }

        return vm.ffi(args);
    }

    function _parseResult(bytes memory result) private returns (bytes32 salt, address expectedAddress) {
        string[] memory lines = vm.split(string(result), "\n");
        expectedAddress = _extractAddress(lines);
        salt = _extractSalt(lines);
    }

    function _extractAddress(string[] memory lines) private returns (address) {
        for (uint256 i = 0; i < lines.length; i++) {
            if (LibString.indexOf(lines[i], "Address:") != LibString.NOT_FOUND) {
                return _parseAddressFromLine(lines[i]);
            }
        }
        revert("Address not found in result");
    }

    function _extractSalt(string[] memory lines) private returns (bytes32) {
        for (uint256 i = 0; i < lines.length; i++) {
            if (LibString.indexOf(lines[i], "Salt:") != LibString.NOT_FOUND) {
                return _parseSaltFromLine(lines[i]);
            }
        }
        revert("Salt not found in result");
    }

    function _parseAddressFromLine(string memory line) private returns (address) {
        bytes memory lineBytes = bytes(line);
        for (uint256 j = 0; j < lineBytes.length - 1; j++) {
            if (lineBytes[j] == "0" && lineBytes[j + 1] == "x") {
                return vm.parseAddress(LibString.slice(line, j, j + 42));
            }
        }
        revert("No address found in line");
    }

    function _parseSaltFromLine(string memory line) private returns (bytes32) {
        bytes memory lineBytes = bytes(line);
        for (uint256 j = 0; j < lineBytes.length - 1; j++) {
            if (lineBytes[j] == "0" && lineBytes[j + 1] == "x") {
                return vm.parseBytes32(LibString.slice(line, j, j + 66));
            }
        }
        revert("No salt found in line");
    }

    function mineForLimitOrderBook(
        address poolManager,
        address zoraFactory,
        address zoraHookRegistry,
        address owner,
        address weth,
        address caller
    ) internal returns (DeterministicContractConfig memory config) {
        bytes memory creationCode = abi.encodePacked(
            type(ZoraLimitOrderBook).creationCode,
            abi.encode(poolManager, zoraFactory, zoraHookRegistry, owner, weth)
        );
        bytes32 initCodeHash = keccak256(creationCode);

        console2.log("\n=== Mining Limit Order Book Address ===");

        (bytes32 salt, address expectedAddress) = mineSaltWithCaller(
            address(ImmutableCreate2FactoryUtils.IMMUTABLE_CREATE2_FACTORY),
            initCodeHash,
            "7777777",
            caller // First 20 bytes of salt must match caller
        );

        console2.log("Limit Order Book Salt:", vm.toString(salt));
        console2.log("Limit Order Book Address:", expectedAddress);

        config.salt = salt;
        config.deployedAddress = expectedAddress;
        config.creationCode = creationCode;
        config.constructorArgs = abi.encode(poolManager, zoraFactory, zoraHookRegistry, owner, weth);
        config.contractName = "ZoraLimitOrderBook";
    }

    function mineForSwapRouter(
        address poolManager,
        address zoraLimitOrderBook,
        address swapRouter,
        address permit2,
        address owner,
        address caller
    ) internal returns (DeterministicContractConfig memory config) {
        bytes memory creationCode = abi.encodePacked(
            type(SwapWithLimitOrders).creationCode,
            abi.encode(poolManager, zoraLimitOrderBook, swapRouter, permit2, owner)
        );
        bytes32 initCodeHash = keccak256(creationCode);

        console2.log("\n=== Mining Swap Router Address ===");

        (bytes32 salt, address expectedAddress) = mineSaltWithCaller(
            address(ImmutableCreate2FactoryUtils.IMMUTABLE_CREATE2_FACTORY),
            initCodeHash,
            "7777777",
            caller // First 20 bytes of salt must match caller
        );

        console2.log("Swap Router Salt:", vm.toString(salt));
        console2.log("Swap Router Address:", expectedAddress);

        config.salt = salt;
        config.deployedAddress = expectedAddress;
        config.creationCode = creationCode;
        config.constructorArgs = abi.encode(poolManager, zoraLimitOrderBook, swapRouter, permit2, owner);
        config.contractName = "SwapWithLimitOrders";
    }

    function run() public {
        // Read existing deployment to get dependencies
        CoinsDeployment memory deployment = readDeployment();

        require(deployment.zoraFactory != address(0), "ZORA_FACTORY not deployed");
        require(deployment.zoraHookRegistry != address(0), "ZORA_HOOK_REGISTRY not deployed");

        address caller = vm.envAddress("DEPLOYER");
        address proxyAdmin = getProxyAdmin();
        address poolManager = getUniswapV4PoolManager();
        address swapRouter = getUniswapSwapRouter();
        address weth = getWeth();

        console2.log("Deployer (caller):", caller);
        console2.log("Note: First 20 bytes of salt will be set to deployer address");

        // Mine salt for limit order book
        DeterministicContractConfig memory limitOrderBookConfig = mineForLimitOrderBook(
            poolManager,
            deployment.zoraFactory,
            deployment.zoraHookRegistry,
            proxyAdmin,
            weth,
            caller
        );

        // Mine salt for swap router (using the computed limit order book address)
        DeterministicContractConfig memory swapRouterConfig = mineForSwapRouter(
            poolManager,
            limitOrderBookConfig.deployedAddress,
            swapRouter,
            PERMIT2,
            proxyAdmin,
            caller
        );

        // Save deterministic configs
        saveDeterministicContractConfig(limitOrderBookConfig, "zoraLimitOrderBook");
        saveDeterministicContractConfig(swapRouterConfig, "zoraRouter");

        // Save to deployment file
        deployment.zoraLimitOrderBook = limitOrderBookConfig.deployedAddress;
        deployment.zoraRouter = swapRouterConfig.deployedAddress;
        saveDeployment(deployment);

        console2.log("\n=== Mined Salts and Addresses ===");
        console2.log("LIMIT_ORDER_BOOK_SALT:", vm.toString(limitOrderBookConfig.salt));
        console2.log("ZORA_LIMIT_ORDER_BOOK:", limitOrderBookConfig.deployedAddress);
        console2.log("SWAP_ROUTER_SALT:", vm.toString(swapRouterConfig.salt));
        console2.log("ZORA_ROUTER:", swapRouterConfig.deployedAddress);
        console2.log("\nConfiguration files saved to deterministicConfig/");
        console2.log("  - zoraLimitOrderBook.json");
        console2.log("  - zoraRouter.json");
        console2.log("\nNext steps:");
        console2.log("1. Run DeployLimitOrders.s.sol with Turnkey private key to deploy");
        console2.log("   ./scripts/run-forge-script.sh DeployLimitOrders.s.sol base --deploy");
    }
}
