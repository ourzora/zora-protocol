import { VitePluginRadar } from "vite-plugin-radar";
import { defineConfig } from "vocs";
import remarkMermaid from "remark-mermaidjs";

export default defineConfig({
  title: "ZORA Docs",
  titleTemplate: "%s | ZORA Docs",
  iconUrl: "/brand/zorb-logo.png",
  logoUrl: "/brand/zorb-logo.png",
  ogImageUrl: "https://docs.zora.co/brand/og.jpg",
  basePath: process.env.BASE_PATH,
  rootDir: ".",
  topNav: [
    {
      text: "Coins SDK",
      link: "/coins/sdk",
      match: "/coins/sdk",
    },
    {
      text: "Coins Protocol",
      link: "/coins",
      match: "/coins",
    },
    {
      text: "Changelogs",
      items: [
        {
          text: "Coins Contracts",
          link: "/changelogs/coins",
          match: "/changelogs/coins",
        },
        {
          text: "Coins SDK",
          link: "/changelogs/coins-sdk",
          match: "/changelogs/coins-sdk",
        },
      ],
    },
    {
      text: "Legacy NFT Docs",
      link: "https://nft-docs.zora.co",
      match: "/nft",
    },
  ],
  socials: [
    {
      icon: "github",
      link: "https://github.com/ourzora/zora-protocol",
    },
    {
      icon: "x",
      link: "https://x.com/zoradevs",
    },
  ],
  sidebar: {
    "/coins/contracts": [
      {
        text: "Coins Contracts",
        items: [
          {
            text: "Creating a Coin",
            link: "/coins/contracts/creating-a-coin",
          },
          {
            text: "Architecture",
            link: "/coins/contracts/architecture",
          },
          {
            text: "Hook System",
            link: "/coins/contracts/hook",
          },
          {
            text: "Coin Rewards",
            link: "/coins/contracts/rewards",
          },
          {
            text: "Earning Rewards as a Developer",
            link: "/coins/contracts/earning-referral-rewards",
          },
          {
            text: "Liquidity Migration",
            link: "/coins/contracts/liquidity-migration",
          },
          {
            text: "Metadata",
            link: "/coins/contracts/metadata",
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
                link: "/coins/sdk",
              },
              {
                text: "Create Coin",
                link: "/coins/sdk/create-coin",
              },
              {
                text: "Coins Metadata Builder",
                link: "/coins/sdk/metadata-builder",
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
                ],
              },
            ],
          },
          {
            text: "Contracts",
            items: [
              {
                text: "Creating a Coin",
                link: "/coins/contracts/creating-a-coin",
              },
              {
                text: "Architecture",
                link: "/coins/contracts/architecture",
              },
              {
                text: "Hook System",
                link: "/coins/contracts/hook",
              },
              {
                text: "Coin Rewards",
                link: "/coins/contracts/rewards",
              },
              {
                text: "Earning Rewards as a Developer",
                link: "/coins/contracts/earning-referral-rewards",
              },
              {
                text: "Liquidity Migration",
                link: "/coins/contracts/liquidity-migration",
              },
              {
                text: "Metadata",
                link: "/coins/contracts/metadata",
              },
              {
                text: "Coins License",
                link: "/coins/license",
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
        ],
      },
    ],
  },
  markdown: {
    remarkPlugins: [remarkMermaid],
  },
  vite: {
    build: {
      outDir: ".vercel/output",
    },
    plugins: [
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
