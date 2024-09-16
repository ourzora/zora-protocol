/** ABI parameters for performing a SafeTransferFrom based swap when selling on secondary. */
export const safeTransferSwapAbiParameters = [
  { name: "recipient", internalType: "address payable", type: "address" },
  { name: "minEthToAcquire", internalType: "uint256", type: "uint256" },
  { name: "sqrtPriceLimitX96", internalType: "uint160", type: "uint160" },
] as const;
