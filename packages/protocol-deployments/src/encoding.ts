import {
  Address,
  decodeAbiParameters,
  encodeAbiParameters,
  encodeFunctionData,
} from "viem";
import { uniswapV3SwapRouterABI } from "./generated/wagmi";
import { buySupplyWithSwapRouterHookAddress } from "./generated/wagmi";

import { Hex } from "viem";
import { AbiParametersToPrimitiveTypes, ExtractAbiFunction } from "abitype";

/** ABI parameters for performing a SafeTransferFrom based swap when selling on secondary. */
export const safeTransferSwapAbiParameters = [
  { name: "recipient", internalType: "address payable", type: "address" },
  { name: "minEthToAcquire", internalType: "uint256", type: "uint256" },
  { name: "sqrtPriceLimitX96", internalType: "uint160", type: "uint160" },
] as const;

export const buySupplyWithSwapRouterHookAbiParameters = [
  { name: "buyRecipient", internalType: "address", type: "address" },
  { name: "swapRouterCall", internalType: "bytes", type: "bytes" },
] as const;

export const buySupplyWithSwapRouterHookReturnParameters = [
  { name: "amountCurrency", internalType: "uint256", type: "uint256" },
  { name: "coinsPurchased", internalType: "uint256", type: "uint256" },
] as const;

/**
 * Encodes the calldata for the BuySupplyWithSwapRouterHook.
 *
 * @param buyRecipient - The address of the recipient of the coins that are purchased.
 * @param swapRouterCall - The calldata to send for swapping on the swap router.  For the call, the recipient of the swap
 * must be the hook contract.
 * @returns The encoded calldata.
 */
export const encodeBuySupplyWithSwapRouterHookCalldata = (
  buyRecipient: Address,
  swapRouterCall: Hex,
) => {
  return encodeAbiParameters(buySupplyWithSwapRouterHookAbiParameters, [
    buyRecipient,
    swapRouterCall,
  ]);
};

type ExactInputSingleParams = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<
    typeof uniswapV3SwapRouterABI,
    "exactInputSingle"
  >["inputs"]
>[0];

type ExactInputParams = AbiParametersToPrimitiveTypes<
  ExtractAbiFunction<typeof uniswapV3SwapRouterABI, "exactInput">["inputs"]
>[0];

/**
 * Encodes the call data for buying supply with a single-hop swap router hook.
 * This function creates the hook call and hook data needed to buy Coin supply using ETH through a Uniswap V3 single-hop swap.
 *
 * @param buyRecipient - The address that will receive the coins purchased
 * @param exactInputSingleParams - The parameters for the exactInputSingle function on the swap router (recipient is omitted as it will be set to the hook address)
 * @param chainId - The chain ID to use for getting the hook address
 * @param ethValue - Optional amount of ETH to send with the call to the swap router
 * @returns Object containing the encoded hook call, hook data, and ETH value
 */
export const encodeBuySupplyWithSingleHopSwapRouterHookCall = ({
  buyRecipient,
  exactInputSingleParams,
  chainId,
  ethValue,
}: {
  buyRecipient: Address;
  exactInputSingleParams: Omit<ExactInputSingleParams, "recipient">;
  chainId: keyof typeof buySupplyWithSwapRouterHookAddress;
  // optional amount of ETH to send with the call to the swap router
  ethValue?: bigint;
}) => {
  const hook = buySupplyWithSwapRouterHookAddress[chainId];
  const callToSwapRouter = encodeFunctionData({
    abi: uniswapV3SwapRouterABI,
    functionName: "exactInputSingle",
    args: [
      {
        recipient: hook,
        ...exactInputSingleParams,
      },
    ],
  });

  return {
    hook: encodeBuySupplyWithSwapRouterHookCalldata(hook, callToSwapRouter),
    hookData: encodeBuySupplyWithSwapRouterHookCalldata(
      buyRecipient,
      callToSwapRouter,
    ),
    value: ethValue,
  };
};

/**
 * Encodes the call data for buying supply with a multi-hop swap router hook.
 * This function creates the hook call and hook data needed to buy Coin supply using ETH through a Uniswap V3 multi-hop swap.
 *
 * @param buyRecipient - The address that will receive the coins purchased
 * @param exactInputParams - The parameters for the exactInput function on the swap router (recipient is omitted as it will be set to the hook address)
 * @param chainId - The chain ID to use for getting the hook address
 * @param ethValue - Optional amount of ETH to send with the call to the swap router
 * @returns Object containing the encoded hook call, hook data, and ETH value
 */
export const encodeBuySupplyWithMultiHopSwapRouterHookCall = ({
  buyRecipient,
  exactInputParams,
  chainId,
  ethValue,
}: {
  buyRecipient: Address;
  exactInputParams: Omit<ExactInputParams, "recipient">;
  chainId: keyof typeof buySupplyWithSwapRouterHookAddress;
  // optional amount of ETH to send with the call to the swap router
  ethValue?: bigint;
}) => {
  const hook = buySupplyWithSwapRouterHookAddress[chainId];
  const callToSwapRouter = encodeFunctionData({
    abi: uniswapV3SwapRouterABI,
    functionName: "exactInput",
    args: [
      {
        recipient: hook,
        ...exactInputParams,
      },
    ],
  });

  return {
    hook: encodeBuySupplyWithSwapRouterHookCalldata(hook, callToSwapRouter),
    hookData: encodeBuySupplyWithSwapRouterHookCalldata(
      buyRecipient,
      callToSwapRouter,
    ),
    value: ethValue,
  };
};

/**
 * Decodes the return data from the BuySupplyWithSwapRouterHook.
 *
 * @param returnData - The return data from the BuySupplyWithSwapRouterHook.
 * @returns The decoded return data.
 */
export const decodeBuySupplyWithSwapRouterHookReturn = (returnData: Hex) => {
  const result = decodeAbiParameters(
    buySupplyWithSwapRouterHookReturnParameters,
    returnData,
  );

  return {
    amountCurrency: result[0],
    coinsPurchased: result[1],
  };
};
