export type SortOption =
  | "mcap"
  | "volume"
  | "new"
  | "gainers"
  | "last-traded"
  | "last-traded-unique"
  | "trending"
  | "featured";
export type CoinType = "trend" | "creator-coin" | "post";
export type TypeOption = "all" | CoinType;

export type PageInfo = { endCursor?: string; hasNextPage: boolean };

export type CoinNode = {
  name?: string;
  address?: string;
  coinType?: string;
  marketCap?: string;
  volume24h?: string;
  marketCapDelta24h?: string;
};

export const SORT_LABELS: Record<SortOption, string> = {
  mcap: "Top by Market Cap",
  volume: "Top by 24h Volume",
  new: "New",
  gainers: "Top Gainers (24h)",
  "last-traded": "Last Traded",
  "last-traded-unique": "Last Traded (Unique)",
  trending: "Trending",
  featured: "Featured",
};

export const TYPE_LABELS: Record<TypeOption, string> = {
  all: "all",
  trend: "trends",
  "creator-coin": "creator coins",
  post: "posts",
};

export const COIN_TYPE_DISPLAY: Record<string, string> = {
  CONTENT: "post",
  CREATOR: "creator-coin",
  TREND: "trend",
};
