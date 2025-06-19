import {
  encodeBuySupplyWithMultiHopSwapRouterHookCall,
  wethAddress,
} from "@zoralabs/protocol-deployments";
import { InitialPurchaseCurrency } from "../actions/createCoin";
import { Address, concat, Hex, pad, toHex } from "viem";
import { ZORA_ADDRESS } from "./poolConfigUtils";
import { base } from "viem/chains";

const BASE_UDSC_ADDRESS = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";

const USDC_ZORA_FEE = 3000;
const WETH_BASE_FEE = 3000;

const encodeFee = (fee: number) => pad(toHex(fee), { size: 3 });

export const getPrepurchaseHook = async ({
  payoutRecipient,
  initialPurchase,
  chainId,
}: {
  initialPurchase: {
    currency: InitialPurchaseCurrency;
    amount: bigint;
    amountOutMinimum?: bigint;
  };
  payoutRecipient: Address;
  chainId: number;
}) => {
  if (
    initialPurchase.currency !== InitialPurchaseCurrency.ETH &&
    chainId !== base.id
  ) {
    throw new Error("Initial purchase currency and/or chain not supported");
  }

  const path = concat([
    wethAddress[base.id],
    encodeFee(WETH_BASE_FEE),
    BASE_UDSC_ADDRESS,
    encodeFee(USDC_ZORA_FEE),
    ZORA_ADDRESS,
  ]);

  return encodeBuySupplyWithMultiHopSwapRouterHookCall({
    ethValue: initialPurchase.amount,
    buyRecipient: payoutRecipient,
    exactInputParams: {
      path,
      amountIn: initialPurchase.amount,
      amountOutMinimum: initialPurchase.amountOutMinimum || 0n,
    },
    chainId: base.id,
  }) as {
    hook: Address;
    hookData: Hex;
    value: bigint;
  };
};
