import { VitePluginRadar } from "vite-plugin-radar";
import { defineConfig } from "vocs";
import vercel from "vite-plugin-vercel";

export default defineConfig({
  title: "ZORA Docs",
  titleTemplate: "%s | ZORA Docs",
  iconUrl: "https://docs.zora.co/brand/zorb-logo.png",
  logoUrl: "https://docs.zora.co/brand/zorb-logo.png",
  ogImageUrl: "https://docs.zora.co/brand/og.png",
  basePath: process.env.BASE_PATH,
  rootDir: ".",
  topNav: [
    {
      text: "Coins",
      link: "/coins",
      match: "/coins",
    },
    {
      text: "Mints",
      items: [
        { text: "Contracts", link: "/contracts/intro" },
        { text: "SDKs", link: "/protocol-sdk/introduction" },
      ],
    },
    {
      text: "Zora Network",
      link: "/zora-network/intro",
      match: "/zora-network",
    },
    {
      text: "Changelogs",
      link: "/changelogs/protocol-sdk",
      match: "/changelogs",
    },
  ],
  socials: [
    {
      icon: "github",
      link: "https://github.com/ourzora/zora-protocol",
    },
  ],
  sidebar: {
    "/contracts": [
      {
        text: "Mint Contracts",
        items: [
          {
            text: "Introduction",
            link: "/contracts/intro",
          },
          { text: "Deployments", link: "/contracts/deployments" },
          {
            text: "Factories",
            link: "/contracts/factories",
          },
          {
            text: "Protocol Rewards",
            link: "/contracts/rewards",
          },
          {
            text: "Events",
            link: "/contracts/events",
          },
          {
            text: "1155 Contracts",
            collapsed: false,
            items: [
              {
                text: "Creating a Contract",
                link: "/contracts/Deploy1155Contract",
              },
              {
                text: "Contract and Token Metadata",
                link: "/contracts/Metadata",
              },
              {
                text: "Creating a Token",
                link: "/contracts/Creating1155Token",
              },
              {
                text: "Selling an Token",
                link: "/contracts/Selling1155",
              },
              {
                text: "Minting Tokens",
                link: "/contracts/Minting1155",
              },
              {
                text: "Permission",
                link: "/contracts/Permissions1155",
              },
              {
                text: "Timed Sale with Secondary",
                link: "/contracts/ZoraTimedSaleStrategy",
              },
              {
                text: "ERC20 Minter",
                link: "/contracts/ERC20Minter",
              },
            ],
          },
          {
            text: "721 Contracts",
            collapsed: true,
            items: [
              {
                text: "ZORANFTCreator",
                link: "/contracts/ZORANFTCreator",
              },
              {
                text: "ERC721Drop",
                link: "/contracts/ERC721Drop",
              },
              {
                text: "EditionMetadataRenderer",
                link: "/contracts/EditionMetadataRenderer",
              },
              {
                text: "JSONExtensionRegistry",
                link: "/contracts/JSONExtensionRegistry",
              },
              {
                text: "DropMetadataRenderer",
                link: "/contracts/DropMetadataRenderer",
              },
            ],
          },
          {
            text: "Comments",
            link: "/contracts/Comments",
          },
          {
            text: "Cointags",
            link: "/contracts/cointags",
          },
        ],
      },
    ],
    "/protocol-sdk": [
      {
        text: "Mint SDKs",
        items: [
          {
            text: "Introduction",
            link: "/protocol-sdk/introduction",
          },
          {
            text: "Protocol Deployments Package",
            link: "/protocol-sdk/protocol-deployments",
          },
          {
            text: "Creator Client",
            items: [
              {
                text: "create 1155s",
                link: "/protocol-sdk/creator/onchain",
                items: [
                  {
                    text: "erc-20 mints",
                    link: "/protocol-sdk/creator/erc20-mints",
                  },
                  {
                    text: "split payouts",
                    link: "/protocol-sdk/creator/splits",
                  },
                ],
              },
            ],
          },
          {
            text: "Protocol Rewards and Secondary Royalties",
            items: [
              {
                text: "getRewardsBalances",
                link: "/protocol-sdk/creator/getRewardsBalances",
              },
              {
                text: "withdrawRewards",
                link: "/protocol-sdk/creator/withdrawRewards",
              },
            ],
          },
          {
            text: "Metadata",
            items: [
              {
                text: "building token metadata",
                link: "/protocol-sdk/metadata/token-metadata",
              },
              {
                text: "building contract metadata",
                link: "/protocol-sdk/metadata/contract-metadata",
              },
            ],
          },
          {
            text: "Collector Client",
            items: [
              {
                text: "getToken",
                link: "/protocol-sdk/collect/getToken",
              },
              {
                text: "getTokensOfContract",
                link: "/protocol-sdk/collect/getTokensOfContract",
              },
              {
                text: "mint",
                link: "/protocol-sdk/collect/mint",
              },
            ],
          },
          {
            text: "Secondary Market",
            items: [
              {
                text: "buy1155OnSecondary",
                link: "/protocol-sdk/collect/buy1155OnSecondary",
              },
              {
                text: "sell1155OnSecondary",
                link: "/protocol-sdk/collect/sell1155OnSecondary",
              },
              {
                text: "getSecondaryInfo",
                link: "/protocol-sdk/collect/getSecondaryInfo",
              },
            ],
          },
        ],
      },
    ],
    "/coins": [
      {
        text: "Coins",
        items: [
          {
            text: "Introduction",
            link: "/coins",
          },
          {
            text: "SDK",
            items: [
              {
                text: "Getting Started",
                link: "/coins/sdk/getting-started",
              },
              {
                text: "Create Coin",
                link: "/coins/sdk/create-coin",
              },
              {
                text: "Trade Coin",
                link: "/coins/sdk/trade-coin",
              },
              {
                text: "Update Coin",
                link: "/coins/sdk/update-coin",
              },
              {
                text: "Coins Metadata",
                link: "/coins/sdk/metadata",
              },
              {
                text: "Coin Queries",
                items: [
                  {
                    text: "Queries Overview",
                    link: "/coins/sdk/queries",
                  },
                  {
                    text: "Coin Details",
                    link: "/coins/sdk/queries/coin",
                  },
                  {
                    text: "Profile Queries",
                    link: "/coins/sdk/queries/profile",
                  },
                  {
                    text: "Explore Coins",
                    link: "/coins/sdk/queries/explore",
                  },
                  {
                    text: "Onchain Queries",
                    link: "/coins/sdk/queries/onchain",
                  },
                ],
              },
            ],
          },
          {
            text: "Contracts",
            items: [
              {
                text: "Coin Factory",
                link: "/coins/contracts/factory",
              },
              {
                text: "Coin Contract",
                link: "/coins/contracts/coin",
              },
            ],
          },
        ],
      },
    ],
    "/changelogs": [
      {
        text: "Changelogs",
        items: [
          {
            text: "@zoralabs/coins",
            link: "/changelogs/coins",
          },
          {
            text: "@zoralabs/coins-sdk",
            link: "/changelogs/coins-sdk",
          },
          {
            text: "@zoralabs/protocol-deployments",
            link: "/changelogs/protocol-deployments",
          },
          {
            text: "@zoralabs/protocol-sdk",
            link: "/changelogs/protocol-sdk",
          },
          {
            text: "@zoralabs/zora-1155-contracts",
            link: "/changelogs/1155-contracts",
          },
          {
            text: "@zoralabs/cointags-contracts",
            link: "/changelogs/cointags",
          },
        ],
      },
    ],
    "/zora-network": [
      {
        text: "ZORA Network",
        items: [
          {
            text: "Introduction",
            link: "/zora-network/intro",
          },
          { text: "Network", link: "/zora-network/network" },
          { text: "ETH vs ZORA", link: "/zora-network/ethvszora" },
          { text: "Bridging", link: "/zora-network/bridging" },
          { text: "API Access", link: "/zora-network/api-access" },
          { text: "Contracts", link: "/zora-network/contracts" },
          { text: "Metamask", link: "/zora-network/metamask" },
          { text: "Deployments", link: "/zora-network/deployments" },
          {
            text: "Status",
            link: "https://status.zora.energy/",
          },
        ],
      },
    ],
  },
  vite: {
    plugins: [
      vercel(),
      ...(process.env.NODE_ENV === "production"
        ? [
            VitePluginRadar({
              analytics: {
                id: "G-CDE92MLBTZ",
              },
            }) as any,
          ]
        : []),
    ],
    esbuild: {
      supported: {
        "top-level-await": true, //browsers can handle top-level-await features
      },
    },
  },
});
