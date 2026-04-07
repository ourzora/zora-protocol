const SCALE = 1e18;
const ONE_SCALED = BigInt(SCALE);

/**
 * Increase a base amount by a slippage percentage
 *
 * @remarks
 * This is useful when trying to calculate how much a user would at maximum pay,
 * when allowing for the specified amount of slippage (i.e. when buying 1155s).
 *
 * @param amount - the amount to calculate with slippage (if a bigint is passed we assume wei, otherwise we assume ether/usd/etc)
 * @param slippage - the slippage percantage as a fraction (i.e. 5% -> 0.05)
 * @returns the amount increased by the slippage
 */
export function calculateSlippageUp<
  T extends bigint | number | string,
  R = T extends bigint ? bigint : number,
>(amount: T, slippage: number): R {
  return typeof amount === "bigint"
    ? (((amount * (ONE_SCALED + BigInt(slippage * SCALE))) / ONE_SCALED) as R)
    : ((parseFloat(String(amount)) * (1 + slippage)) as R);
}

/**
 * Decrease a base amount by a slippage percentage
 *
 * @remarks
 * This is useful when trying to calculate how much a user would at minimum receive,
 * when allowing for the specified amount of slippage (i.e. when selling 1155s).
 *
 * @param amount - the amount to calculate with slippage (if a bigint is passed we assume wei, otherwise we assume ether/usd/etc)
 * @param slippage - the slippage percantage as a fraction (i.e. 5% -> 0.05)
 * @returns the amount decreased by the slippage
 */
export function calculateSlippageDown<
  T extends bigint | number | string,
  R = T extends bigint ? bigint : number,
>(amount: T, slippage: number): R {
  return typeof amount === "bigint"
    ? (((amount * (ONE_SCALED - BigInt(slippage * SCALE))) / ONE_SCALED) as R)
    : ((parseFloat(String(amount)) * (1 - slippage)) as R);
}
