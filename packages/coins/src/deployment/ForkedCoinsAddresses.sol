// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Minimal deployment base for coins tests
/// @dev Provides hardcoded deployment addresses for testing
contract ForkedCoinsAddresses {
    struct CoinsDeployment {
        // Factory
        address zoraFactory;
        address zoraFactoryImpl;
        // Implementation
        address coinV3Impl;
        address coinV4Impl;
        address creatorCoinImpl;
        string coinVersion;
        // hooks
        address buySupplyWithSwapRouterHook;
        address zoraV4CoinHook;
        address hookUpgradeGate;
        // trusted sender lookup
        address trustedMsgSenderLookup;
        // Hook deployment salt (for deterministic deployment)
        bytes32 zoraV4CoinHookSalt;
        bool isDev;
        // Hook registry
        address zoraHookRegistry;
        // Limit order book
        address zoraLimitOrderBook;
        address swapWithLimitOrdersRouter;
        address orderBookAuthority;
    }

    address internal constant ZORA = 0x1111111111166b7FE7bd91427724B487980aFc69;

    function readDeployment() internal pure returns (CoinsDeployment memory deployment) {
        return readDeployment(false);
    }

    function readDeployment(bool dev) internal pure returns (CoinsDeployment memory deployment) {
        // Hardcoded Base mainnet deployment addresses
        deployment.zoraFactory = 0x777777751622c0d3258f214F9DF38E35BF45baF3;
        deployment.zoraFactoryImpl = 0x8Ec7f068A77fa5FC1925110f82381374BA054Ff2;
        deployment.coinV3Impl = 0x45Bf86430af7CD071Ea23aE52325A78C8d12aD5a;
        deployment.coinV4Impl = 0x7Cad62748DDf516CF85bC2C05C14786D84Cf861c;
        deployment.creatorCoinImpl = 0x36853f9f48fAEe51Bd3db15db21EB4B9038bB795;
        deployment.coinVersion = "2.3.0";
        deployment.buySupplyWithSwapRouterHook = 0xd8CC7bCA1dE52eA788829B16E375e9B96C18D433;
        deployment.zoraV4CoinHook = 0xC8d077444625eB300A427a6dfB2b1DBf9b159040;
        deployment.hookUpgradeGate = 0xD88f6BdD765313CaFA5888C177c325E2C3AbF2D2;
        deployment.zoraV4CoinHookSalt = 0x0000000000000000000000000000000000000000000000000000000000001624;
        deployment.zoraHookRegistry = 0x777777C4c14b133858c3982D41Dbf02509fc18d7;
        deployment.isDev = dev;
    }
}
