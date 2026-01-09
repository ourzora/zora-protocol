// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BaseTest} from "./utils/BaseTest.sol";
import {CoinConfigurationVersions} from "../src/libs/CoinConfigurationVersions.sol";
import {CoinDopplerMultiCurve} from "../src/libs/CoinDopplerMultiCurve.sol";
import {V4Liquidity} from "../src/libs/V4Liquidity.sol";
import {LpPosition} from "../src/types/LpPosition.sol";
import {PoolConfiguration} from "../src/interfaces/ICoin.sol";
import {CoinConstants} from "../src/libs/CoinConstants.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ContentCoin} from "../src/ContentCoin.sol";
import {ZoraV4CoinHook} from "../src/hooks/ZoraV4CoinHook.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

contract V4LiquidityTest is BaseTest {
    MockERC20 internal mockERC20A;

    function setUp() public override {
        super.setUp();
        mockERC20A = new MockERC20("MockERC20A", "MCKA");
    }

    function _poolConfigWithDuplicatePositions(address currency) private pure returns (bytes memory poolConfig) {
        // Create configuration that will produce duplicate positions
        int24[] memory tickLower_ = new int24[](2);
        tickLower_[0] = -54000;
        tickLower_[1] = -54000; // Same as first curve

        int24[] memory tickUpper_ = new int24[](2);
        tickUpper_[0] = 7000;
        tickUpper_[1] = 7000; // Same as first curve

        uint16[] memory numDiscoveryPositions_ = new uint16[](2);
        numDiscoveryPositions_[0] = 5;
        numDiscoveryPositions_[1] = 5;

        uint256[] memory maxDiscoverySupplyShare_ = new uint256[](2);
        maxDiscoverySupplyShare_[0] = 100000000000000000; // 0.1e18
        maxDiscoverySupplyShare_[1] = 100000000000000000; // 0.1e18

        poolConfig = CoinConfigurationVersions.encodeDopplerMultiCurveUniV4(currency, tickLower_, tickUpper_, numDiscoveryPositions_, maxDiscoverySupplyShare_);
    }

    function _countDuplicatePositions(LpPosition[] memory positions) private pure returns (uint256 duplicateCount) {
        for (uint256 i = 0; i < positions.length; i++) {
            for (uint256 j = i + 1; j < positions.length; j++) {
                if (positions[i].tickLower == positions[j].tickLower && positions[i].tickUpper == positions[j].tickUpper) {
                    duplicateCount++;
                    break; // Only count each unique duplicate once
                }
            }
        }
    }

    function test_calculatePositionsWithDuplicateConfigCreatesDuplicates() public view {
        address currency = address(mockERC20A);
        bytes memory poolConfig = _poolConfigWithDuplicatePositions(currency);

        (, PoolConfiguration memory poolConfiguration) = CoinDopplerMultiCurve.setupPool(true, poolConfig);

        LpPosition[] memory positions = CoinDopplerMultiCurve.calculatePositions(
            true, // isCoinToken0
            poolConfiguration,
            CoinConstants.CONTENT_COIN_MARKET_SUPPLY
        );

        uint256 duplicateCount = _countDuplicatePositions(positions);
        assertGt(duplicateCount, 0, "Should have duplicate positions");
    }

    function test_dedupePositionsMergesDuplicates() public view {
        address currency = address(mockERC20A);
        bytes memory poolConfig = _poolConfigWithDuplicatePositions(currency);

        (, PoolConfiguration memory poolConfiguration) = CoinDopplerMultiCurve.setupPool(true, poolConfig);

        LpPosition[] memory originalPositions = CoinDopplerMultiCurve.calculatePositions(
            true, // isCoinToken0
            poolConfiguration,
            CoinConstants.CONTENT_COIN_MARKET_SUPPLY
        );

        uint256 originalDuplicateCount = _countDuplicatePositions(originalPositions);
        assertGt(originalDuplicateCount, 0, "Should have duplicate positions to test deduplication");

        // Deduplicate the positions
        LpPosition[] memory dedupedPositions = V4Liquidity.dedupePositions(originalPositions);

        // Verify no duplicates exist in deduped array
        uint256 dedupedDuplicateCount = _countDuplicatePositions(dedupedPositions);
        assertEq(dedupedDuplicateCount, 0, "Should have no duplicates after deduplication");

        // Verify that array is smaller after deduplication
        assertLt(dedupedPositions.length, originalPositions.length, "Deduped array should be smaller");

        // Calculate total liquidity before and after deduplication
        uint256 totalOriginalLiquidity = 0;
        uint256 totalDedupedLiquidity = 0;

        for (uint256 i = 0; i < originalPositions.length; i++) {
            totalOriginalLiquidity += originalPositions[i].liquidity;
        }

        for (uint256 i = 0; i < dedupedPositions.length; i++) {
            totalDedupedLiquidity += dedupedPositions[i].liquidity;
        }

        assertEq(totalOriginalLiquidity, totalDedupedLiquidity, "Total liquidity should be preserved");
    }

    function test_memoryStructModification() public pure {
        // this test shows that we can modify a struct in memory and it will be reflected in the array
        LpPosition[] memory positions = new LpPosition[](2);
        positions[0] = LpPosition({tickLower: -100, tickUpper: 100, liquidity: 1000});
        positions[1] = LpPosition({tickLower: -200, tickUpper: 200, liquidity: 2000});

        LpPosition memory pos = positions[0];
        pos.liquidity += 500;
        pos = positions[1];
        pos.liquidity = 3000;

        // The array element should be modified
        assertEq(positions[0].liquidity, 1500, "Array element should change when modifying copy");
        assertEq(positions[1].liquidity, 3000, "Array element should change when modifying copy");
    }

    function test_mstoreArrayLength() public pure {
        LpPosition[] memory positions = new LpPosition[](5);
        positions[0] = LpPosition({tickLower: -100, tickUpper: 100, liquidity: 1000});
        positions[1] = LpPosition({tickLower: -200, tickUpper: 200, liquidity: 2000});
        positions[2] = LpPosition({tickLower: -300, tickUpper: 300, liquidity: 3000});
        positions[3] = LpPosition({tickLower: -400, tickUpper: 400, liquidity: 4000});
        positions[4] = LpPosition({tickLower: -500, tickUpper: 500, liquidity: 5000});

        assertEq(positions.length, 5, "Initial length should be 5");

        assembly {
            mstore(positions, 2)
        }

        assertEq(positions.length, 2, "Length should be 2 after mstore");
        assertEq(positions[0].liquidity, 1000, "First element should be preserved");
        assertEq(positions[1].liquidity, 2000, "Second element should be preserved");
    }

    function test_deployedCoinWithDuplicateConfigHasNoDuplicatePositions() public {
        address currency = address(mockERC20A);

        address[] memory owners = new address[](1);
        owners[0] = users.creator;

        bytes memory poolConfig = _poolConfigWithDuplicatePositions(currency);

        (address coinAddress, ) = factory.deploy(
            users.creator,
            owners,
            "https://test.com",
            DEFAULT_NAME,
            DEFAULT_SYMBOL,
            poolConfig,
            address(0),
            address(0),
            bytes(""),
            bytes32(0)
        );

        ContentCoin coinV4 = ContentCoin(payable(coinAddress));

        // get hooks
        PoolKey memory poolKey = coinV4.getPoolKey();
        LpPosition[] memory positions = ZoraV4CoinHook(payable(address(coinV4.hooks()))).getPoolCoin(poolKey).positions;

        // Verify no duplicate positions exist in the deployed coin (deduplication worked during deployment)
        uint256 duplicateCount = _countDuplicatePositions(positions);
        assertEq(duplicateCount, 0, "Should have no duplicates after deployment");
    }
}
