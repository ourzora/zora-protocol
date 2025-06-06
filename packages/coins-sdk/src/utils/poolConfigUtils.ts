import { encodeMultiCurvePoolConfig } from "@zoralabs/protocol-deployments";
import { parseUnits, zeroAddress } from "viem";
import { base, baseSepolia } from "viem/chains";

const ZORA_DECIMALS = 18;

/**
 * =========================
 * COIN_ETH_PAIR_POOL_CONFIG
 * =========================
 */

export const ZORA_ADDRESS = "0x1111111111166b7fe7bd91427724b487980afc69";

const COIN_ETH_PAIR_LOWER_TICK = -250000;
const COIN_ETH_PAIR_UPPER_TICK = -195_000;
const COIN_ETH_PAIR_NUM_DISCOVERY_POSITIONS = 11;
const COIN_ETH_PAIR_MAX_DISCOVERY_SUPPLY_SHARE = parseUnits("0.05", 18);

export const COIN_ETH_PAIR_POOL_CONFIG = {
  [base.id]: encodeMultiCurvePoolConfig({
    currency: zeroAddress,
    tickLower: [COIN_ETH_PAIR_LOWER_TICK],
    tickUpper: [COIN_ETH_PAIR_UPPER_TICK],
    numDiscoveryPositions: [COIN_ETH_PAIR_NUM_DISCOVERY_POSITIONS],
    maxDiscoverySupplyShare: [COIN_ETH_PAIR_MAX_DISCOVERY_SUPPLY_SHARE],
  }),
  [baseSepolia.id]: encodeMultiCurvePoolConfig({
    currency: zeroAddress,
    tickLower: [COIN_ETH_PAIR_LOWER_TICK],
    tickUpper: [COIN_ETH_PAIR_UPPER_TICK],
    numDiscoveryPositions: [COIN_ETH_PAIR_NUM_DISCOVERY_POSITIONS],
    maxDiscoverySupplyShare: [COIN_ETH_PAIR_MAX_DISCOVERY_SUPPLY_SHARE],
  }),
};

const COIN_ZORA_PAIR_LOWER_TICK = -138_000; // ( -250000 in ETH land ~= $23 = -138_000 in Zora token land at .022)
const COIN_ZORA_PAIR_UPPER_TICK = -81_000; // (-195_000 ~= 5782 =  -81_000 in Zora token land at .022)
const COIN_ZORA_PAIR_NUM_DISCOVERY_POSITIONS = 11;
const COIN_ZORA_PAIR_MAX_DISCOVERY_SUPPLY_SHARE = parseUnits(
  "0.05",
  ZORA_DECIMALS,
);

export const COIN_ZORA_PAIR_POOL_CONFIG = {
  [base.id]: encodeMultiCurvePoolConfig({
    currency: ZORA_ADDRESS,
    tickLower: [COIN_ZORA_PAIR_LOWER_TICK],
    tickUpper: [COIN_ZORA_PAIR_UPPER_TICK],
    numDiscoveryPositions: [COIN_ZORA_PAIR_NUM_DISCOVERY_POSITIONS],
    maxDiscoverySupplyShare: [COIN_ZORA_PAIR_MAX_DISCOVERY_SUPPLY_SHARE],
  }),
};
