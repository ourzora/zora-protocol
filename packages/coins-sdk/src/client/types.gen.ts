// This file is auto-generated by @hey-api/openapi-ts

export type GetCoinData = {
  body?: never;
  path?: never;
  query: {
    address: string;
    chain?: number;
  };
  url: "/coin";
};

export type GetCoinResponses = {
  /**
   * response
   */
  200: {
    zora20Token?: {
      /**
       * The Globally Unique ID of this object
       */
      id?: string;
      name?: string;
      description?: string;
      address?: string;
      symbol?: string;
      totalSupply?: string;
      totalVolume?: string;
      volume24h?: string;
      createdAt?: string;
      creatorAddress?: string;
      creatorEarnings?: Array<{
        amount?: {
          currencyAddress?: string;
          amountRaw?: string;
          amountDecimal?: number;
        };
        amountUsd?: string;
      }>;
      marketCap?: string;
      marketCapDelta24h?: string;
      chainId?: number;
      creatorProfile?: string;
      handle?: string;
      avatar?: {
        previewImage?: string;
        blurhash?: string;
        small?: string;
      };
      mediaContent?: string;
      mimeType?: string;
      originalUri?: string;
      previewImage?: string;
      small?: string;
      medium?: string;
      blurhash?: string;
      transfers?: {
        count?: number;
      };
      uniqueHolders?: number;
      zoraComments?: {
        /**
         * Information to aid in pagination.
         */
        pageInfo?: {
          /**
           * When paginating forwards, the cursor to continue.
           */
          endCursor?: string;
          /**
           * When paginating forwards, are there more items?
           */
          hasNextPage?: boolean;
        };
        count?: number;
        edges?: Array<{
          node?: string;
          txHash?: string;
          comment?: string;
          userAddress?: string;
          timestamp?: number;
          userProfile?: string;
          /**
           * The Globally Unique ID of this object
           */
          id?: string;
          handle?: string;
          avatar?: {
            previewImage?: string;
            blurhash?: string;
            small?: string;
          };
        }>;
      };
    };
  };
};

export type GetCoinResponse = GetCoinResponses[keyof GetCoinResponses];

export type GetCoinCommentsData = {
  body?: never;
  path?: never;
  query: {
    address: string;
    chain?: number;
    after?: string;
    count?: number;
  };
  url: "/coinComments";
};

export type GetCoinCommentsResponses = {
  /**
   * response
   */
  200: {
    zora20Token?: {
      zoraComments?: {
        /**
         * Information to aid in pagination.
         */
        pageInfo?: {
          /**
           * When paginating forwards, the cursor to continue.
           */
          endCursor?: string;
          /**
           * When paginating forwards, are there more items?
           */
          hasNextPage?: boolean;
        };
        count?: number;
        edges?: Array<{
          node?: string;
          txHash?: string;
          comment?: string;
          userAddress?: string;
          timestamp?: number;
          userProfile?: string;
          /**
           * The Globally Unique ID of this object
           */
          id?: string;
          handle?: string;
          avatar?: {
            previewImage?: string;
            blurhash?: string;
            small?: string;
          };
          replies?: {
            count?: number;
            edges?: Array<{
              /**
               * The name of the current Object type at runtime.
               */
              __typename?: string;
              node?: {
                /**
                 * The name of the current Object type at runtime.
                 */
                __typename?: string;
                txHash?: string;
                comment?: string;
                userAddress?: string;
                timestamp?: number;
                userProfile?: string;
                /**
                 * The Globally Unique ID of this object
                 */
                id?: string;
                handle?: string;
                avatar?: {
                  previewImage?: string;
                  blurhash?: string;
                  small?: string;
                };
              };
            }>;
          };
        }>;
      };
    };
  };
};

export type GetCoinCommentsResponse =
  GetCoinCommentsResponses[keyof GetCoinCommentsResponses];

export type GetCoinsData = {
  body?: never;
  path?: never;
  query: {
    coins: Array<{
      chainId?: number;
      collectionAddress?: string;
    }>;
  };
  url: "/coins";
};

export type GetCoinsResponses = {
  /**
   * response
   */
  200: {
    zora20Tokens?: Array<{
      /**
       * The Globally Unique ID of this object
       */
      id?: string;
      name?: string;
      description?: string;
      address?: string;
      symbol?: string;
      totalSupply?: string;
      totalVolume?: string;
      volume24h?: string;
      createdAt?: string;
      creatorAddress?: string;
      creatorEarnings?: Array<{
        amount?: {
          currencyAddress?: string;
          amountRaw?: string;
          amountDecimal?: number;
        };
        amountUsd?: string;
      }>;
      marketCap?: string;
      marketCapDelta24h?: string;
      chainId?: number;
      creatorProfile?: string;
      handle?: string;
      avatar?: {
        previewImage?: string;
        blurhash?: string;
        small?: string;
      };
      mediaContent?: string;
      mimeType?: string;
      originalUri?: string;
      previewImage?: string;
      small?: string;
      medium?: string;
      blurhash?: string;
      transfers?: {
        count?: number;
      };
      uniqueHolders?: number;
      zoraComments?: {
        /**
         * Information to aid in pagination.
         */
        pageInfo?: {
          /**
           * When paginating forwards, the cursor to continue.
           */
          endCursor?: string;
          /**
           * When paginating forwards, are there more items?
           */
          hasNextPage?: boolean;
        };
        count?: number;
        edges?: Array<{
          node?: string;
          txHash?: string;
          comment?: string;
          userAddress?: string;
          timestamp?: number;
          userProfile?: string;
          /**
           * The Globally Unique ID of this object
           */
          id?: string;
          handle?: string;
          avatar?: {
            previewImage?: string;
            blurhash?: string;
            small?: string;
          };
        }>;
      };
    }>;
  };
};

export type GetCoinsResponse = GetCoinsResponses[keyof GetCoinsResponses];

export type GetExploreData = {
  body?: never;
  path?: never;
  query: {
    listType:
      | "TOP_GAINERS"
      | "TOP_VOLUME_24H"
      | "MOST_VALUABLE"
      | "NEW"
      | "LAST_TRADED"
      | "LAST_TRADED_UNIQUE";
    count?: number;
    after?: string;
  };
  url: "/explore";
};

export type GetExploreResponses = {
  /**
   * response
   */
  200: {
    exploreList?: {
      edges?: Array<{
        node?: {
          /**
           * The Globally Unique ID of this object
           */
          id?: string;
          name?: string;
          description?: string;
          address?: string;
          symbol?: string;
          totalSupply?: string;
          totalVolume?: string;
          volume24h?: string;
          createdAt?: string;
          creatorAddress?: string;
          creatorEarnings?: Array<{
            amount?: {
              currencyAddress?: string;
              amountRaw?: string;
              amountDecimal?: number;
            };
            amountUsd?: string;
          }>;
          marketCap?: string;
          marketCapDelta24h?: string;
          chainId?: number;
          creatorProfile?: string;
          handle?: string;
          avatar?: {
            previewImage?: string;
            blurhash?: string;
            small?: string;
          };
          mediaContent?: string;
          mimeType?: string;
          originalUri?: string;
          previewImage?: string;
          small?: string;
          medium?: string;
          blurhash?: string;
          transfers?: {
            count?: number;
          };
          uniqueHolders?: number;
        };
        cursor?: string;
      }>;
      /**
       * Information to aid in pagination.
       */
      pageInfo?: {
        /**
         * When paginating forwards, the cursor to continue.
         */
        endCursor?: string;
        /**
         * When paginating forwards, are there more items?
         */
        hasNextPage?: boolean;
      };
    };
  };
};

export type GetExploreResponse = GetExploreResponses[keyof GetExploreResponses];

export type GetProfileData = {
  body?: never;
  path?: never;
  query: {
    identifier: string;
  };
  url: "/profile";
};

export type GetProfileResponses = {
  /**
   * response
   */
  200: {
    profile?: string;
    /**
     * The Globally Unique ID of this object
     */
    id?: string;
    handle?: string;
    avatar?: {
      small?: string;
      medium?: string;
      blurhash?: string;
    };
    username?: string;
    displayName?: string;
    bio?: string;
    website?: string;
    publicWallet?: {
      walletAddress?: string;
    };
    socialAccounts?: {
      instagram?: {
        displayName?: string;
      };
      tiktok?: {
        displayName?: string;
      };
      twitter?: {
        displayName?: string;
      };
    };
    linkedWallets?: {
      edges?: Array<{
        node?: {
          walletType?: "PRIVY" | "EXTERNAL" | "SMART_WALLET";
          walletAddress?: string;
        };
      }>;
    };
  };
};

export type GetProfileResponse = GetProfileResponses[keyof GetProfileResponses];

export type GetProfileBalancesData = {
  body?: never;
  path?: never;
  query: {
    identifier: string;
    count?: number;
    after?: string;
    chainIds?: Array<number>;
  };
  url: "/profileBalances";
};

export type GetProfileBalancesResponses = {
  /**
   * response
   */
  200: {
    profile?: string;
    /**
     * The Globally Unique ID of this object
     */
    id?: string;
    handle?: string;
    avatar?: {
      previewImage?: string;
      blurhash?: string;
      small?: string;
    };
    coinBalances?: {
      count?: number;
      edges?: Array<{
        node?: {
          balance?: string;
          /**
           * The Globally Unique ID of this object
           */
          id?: string;
          coin?: {
            /**
             * The Globally Unique ID of this object
             */
            id?: string;
            name?: string;
            description?: string;
            address?: string;
            symbol?: string;
            totalSupply?: string;
            totalVolume?: string;
            volume24h?: string;
            createdAt?: string;
            creatorAddress?: string;
            creatorEarnings?: Array<{
              amount?: {
                currencyAddress?: string;
                amountRaw?: string;
                amountDecimal?: number;
              };
              amountUsd?: string;
            }>;
            marketCap?: string;
            marketCapDelta24h?: string;
            chainId?: number;
            creatorProfile?: string;
            handle?: string;
            avatar?: {
              previewImage?: string;
              blurhash?: string;
              small?: string;
            };
            mediaContent?: string;
            mimeType?: string;
            originalUri?: string;
            previewImage?: string;
            small?: string;
            medium?: string;
            blurhash?: string;
            transfers?: {
              count?: number;
            };
            uniqueHolders?: number;
          };
        };
      }>;
      /**
       * Information to aid in pagination.
       */
      pageInfo?: {
        /**
         * When paginating forwards, are there more items?
         */
        hasNextPage?: boolean;
        /**
         * When paginating forwards, the cursor to continue.
         */
        endCursor?: string;
      };
    };
  };
};

export type GetProfileBalancesResponse =
  GetProfileBalancesResponses[keyof GetProfileBalancesResponses];

export type ClientOptions = {
  baseUrl:
    | "https://api-sdk.zora.engineering/"
    | "https://api-sdk-staging.zora.engineering/"
    | (string & {});
};
