// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {Coin, CoinConstants} from "../src/Coin.sol";
import {ZoraFactoryImpl} from "../src/ZoraFactoryImpl.sol";
import {ZoraFactory} from "../src/proxy/ZoraFactory.sol";

/// @dev For simulating pre-buys -- eg `forge script script/Simulate.s.sol --private-key $DEPLOYER_PK --rpc-url $BASE_MAINNET_RPC_URL -vvvv`
contract Simulate is Script, CoinConstants {
    // https://basescan.org/address/0x02B2705500096Ff83F9eF78873ca5DFB06C00Ddc
    address internal constant TEST_ZORA_FACTORY_ADDRESS_BASE_MAINNET = 0x02B2705500096Ff83F9eF78873ca5DFB06C00Ddc;
    address internal constant WETH_ADDRESS = 0x4200000000000000000000000000000000000006;

    ZoraFactoryImpl internal factory;
    Coin internal coin;

    function setUp() public {
        factory = ZoraFactoryImpl(TEST_ZORA_FACTORY_ADDRESS_BASE_MAINNET);
    }

    function run() public {
        vm.startBroadcast();

        // Filler
        address payoutAddress = 0x12125c8a52B8E4ed1A28e1f964023b4477f11300;
        address[] memory owners = new address[](1);
        owners[0] = 0x12125c8a52B8E4ed1A28e1f964023b4477f11300;
        string memory uri = "ipfs://bafybeigxwyzkb5rg2tcur4abyaeps56c4vcxytnz7ktrg3nr5dkgrgje7a";
        string memory name = "testcoin";
        string memory symbol = "testcoin";

        // Pool config
        int24 tickLower = -163600; // Starting price * 1B = Starting mcap
        int24 tickUpper = -170000; // Price when tail position liquidity is entered
        uint16 numDisoveryPositions = 99; // More positions = smoother price curve to tickUpper but higher gas cost
        uint256 maxDiscoverySupplyShare = 0.1e18; // Pct of supply to allocate equally across `numDisoveryPositions` between `tickLower` and `tickUpper` above

        bytes memory poolConfig = _generatePoolConfig(WETH_ADDRESS, tickLower, tickUpper, numDisoveryPositions, maxDiscoverySupplyShare);

        // Prebuy order size
        uint256 orderSize = 0.000111 ether;
        (address coinAddress, uint256 coinsPurchased) = factory.deploy{value: orderSize}(
            payoutAddress,
            owners,
            uri,
            name,
            symbol,
            poolConfig,
            payoutAddress,
            orderSize
        );

        vm.stopBroadcast();
    }

    function _generatePoolConfig(
        address currency_,
        int24 tickLower_,
        int24 tickUpper_,
        uint16 numDiscoveryPositions_,
        uint256 maxDiscoverySupplyShare_
    ) internal pure returns (bytes memory) {
        return abi.encode(currency_, tickLower_, tickUpper_, numDiscoveryPositions_, maxDiscoverySupplyShare_);
    }
}
