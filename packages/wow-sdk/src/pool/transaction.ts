import { NoPoolAddressFoundError } from "../errors"

import { PublicClient } from "viem"

import { Address } from "viem"
import { getMarketType } from "../marketType"
import { WowERC20ABI } from "../abi/WowERC20"

export async function getMarketTypeAndPoolAddress({
    tokenAddress,
    publicClient,
    poolAddress: passedInPoolAddress,
}:{
    tokenAddress: Address
    publicClient: PublicClient
    poolAddress?: Address
}){
    const [marketType, poolAddressResult] = await Promise.all([
        getMarketType({
          tokenAddress,
          publicClient,
        }),
        passedInPoolAddress
          ?? publicClient.readContract({
              address: tokenAddress,
              abi: WowERC20ABI,
              functionName: 'poolAddress',
            })
          ,
      ])
    

      if (!poolAddressResult) throw new NoPoolAddressFoundError(tokenAddress)

  return {
    marketType,
    poolAddress: poolAddressResult,
  }
}