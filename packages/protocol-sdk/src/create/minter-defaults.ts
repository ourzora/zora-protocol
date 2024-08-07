import { Concrete } from "src/utils";
import {
  SalesConfigParamsType,
  AllowListParamType,
  Erc20ParamsType,
  FixedPriceParamsType,
  SaleStartAndEnd,
  MaxTokensPerAddress,
  ConcreteSalesConfig,
} from "./types";

// Sales end forever amount (uint64 max)
const SALE_END_FOREVER = 18446744073709551615n;

const DEFAULT_SALE_START_AND_END: Concrete<SaleStartAndEnd> = {
  // Sale start time – defaults to beginning of unix time
  saleStart: 0n,
  // This is the end of uint64, plenty of time
  saleEnd: SALE_END_FOREVER,
};

const DEFAULT_MAX_TOKENS_PER_ADDRESS: Concrete<MaxTokensPerAddress> = {
  maxTokensPerAddress: 0n,
};

const erc20SaleSettingsWithDefaults = (
  params: Erc20ParamsType,
): Concrete<Erc20ParamsType> => ({
  ...DEFAULT_SALE_START_AND_END,
  ...DEFAULT_MAX_TOKENS_PER_ADDRESS,
  ...params,
});

const allowListWithDefaults = (
  allowlist: AllowListParamType,
): Concrete<AllowListParamType> => {
  return {
    ...DEFAULT_SALE_START_AND_END,
    ...allowlist,
  };
};

const fixedPriceSettingsWithDefaults = (
  params: FixedPriceParamsType,
): Concrete<FixedPriceParamsType> => ({
  ...DEFAULT_SALE_START_AND_END,
  ...DEFAULT_MAX_TOKENS_PER_ADDRESS,
  type: "fixedPrice",
  pricePerToken: 0n,
  ...params,
});

const isAllowList = (
  salesConfig: SalesConfigParamsType,
): salesConfig is AllowListParamType => salesConfig.type === "allowlistMint";
const isErc20 = (
  salesConfig: SalesConfigParamsType,
): salesConfig is Erc20ParamsType => salesConfig.type === "erc20Mint";

export const getSalesConfigWithDefaults = (
  salesConfig: SalesConfigParamsType | undefined,
): ConcreteSalesConfig => {
  if (!salesConfig) return fixedPriceSettingsWithDefaults({});
  if (isAllowList(salesConfig)) {
    return allowListWithDefaults(salesConfig);
  }
  if (isErc20(salesConfig)) {
    return erc20SaleSettingsWithDefaults(salesConfig);
  }
  return fixedPriceSettingsWithDefaults(salesConfig);
};
