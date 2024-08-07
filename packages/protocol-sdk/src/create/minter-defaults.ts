import { Concrete } from "src/utils";
import {
  SalesConfigParamsType,
  AllowListParamType,
  Erc20ParamsType,
  FixedPriceParamsType,
  SaleStartAndEnd,
  MaxTokensPerAddress,
  ConcreteSalesConfig,
  TimedSaleParamsType,
} from "./types";
import { fetchTokenMetadata } from "src/ipfs/token-metadata";

// Sales end forever amount (uint64 max)
export const SALE_END_FOREVER = 18446744073709551615n;

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
  ...params,
});

export const parseNameIntoSymbol = (name: string) => {
  if (name === "") {
    throw new Error("Name must be provided to generate a symbol");
  }
  const result =
    "$" +
    name
      // Remove all non-alphanumeric characters
      .replace(/[^a-zA-Z0-9]/g, "")
      // and leading dollar signs
      .replace(/^\$+/, "")
      .toUpperCase()
      // Remove all vowels and spaces
      .replace(/[AEIOU\s]/g, "")
      // Strip down to 4 characters
      .slice(0, 4);

  if (result === "$") {
    throw new Error("Not enough valid characters to generate a symbol");
  }

  return result;
};

async function fetchTokenNameFromMetadata(
  tokenMetadataURI: string,
): Promise<string> {
  const tokenMetadata = await fetchTokenMetadata(tokenMetadataURI);

  if (!tokenMetadata.name) {
    throw new Error("No name found in token metadata");
  }

  return tokenMetadata.name;
}
const timedSaleSettingsWithDefaults = async (
  params: TimedSaleParamsType,
  tokenMetadataURI: string,
): Promise<Concrete<TimedSaleParamsType>> => {
  // If the name is not provided, try to fetch it from the metadata
  const erc20Name =
    params.erc20Name || (await fetchTokenNameFromMetadata(tokenMetadataURI));
  const symbol = params.erc20Symbol || parseNameIntoSymbol(erc20Name);

  return {
    type: "timed",
    ...DEFAULT_SALE_START_AND_END,
    erc20Name,
    erc20Symbol: symbol,
  };
};

const isAllowList = (
  salesConfig: SalesConfigParamsType,
): salesConfig is AllowListParamType => salesConfig.type === "allowlistMint";
const isErc20 = (
  salesConfig: SalesConfigParamsType,
): salesConfig is Erc20ParamsType => salesConfig.type === "erc20Mint";
const isFixedPrice = (
  salesConfig: SalesConfigParamsType,
): salesConfig is FixedPriceParamsType => {
  return (salesConfig as FixedPriceParamsType).pricePerToken > 0n;
};

export const getSalesConfigWithDefaults = async (
  salesConfig: SalesConfigParamsType | undefined,
  tokenMetadataURI: string,
): Promise<ConcreteSalesConfig> => {
  if (!salesConfig) return timedSaleSettingsWithDefaults({}, tokenMetadataURI);
  if (isAllowList(salesConfig)) {
    return allowListWithDefaults(salesConfig);
  }
  if (isErc20(salesConfig)) {
    return erc20SaleSettingsWithDefaults(salesConfig);
  }
  if (isFixedPrice(salesConfig)) {
    return fixedPriceSettingsWithDefaults(salesConfig);
  }

  return timedSaleSettingsWithDefaults(salesConfig, tokenMetadataURI);
};
