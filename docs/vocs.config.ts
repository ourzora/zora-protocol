import { defineConfig } from "vocs";

export default defineConfig({
  title: "ZORA Docs",
  titleTemplate: "%s | ZORA Docs",
  iconUrl: "/Zorb.png",
  logoUrl: "/Zorb.png",
  basePath: process.env.BASE_PATH,
  rootDir: ".",
  topNav: [
    {
      text: "Contracts",
      link: "/contracts/intro",
      match: "/contracts",
    },
    {
      text: "SDKs",
      link: "/protocol-sdk/introduction",
      match: "/protocol-sdk",
    },
    {
      text: "Zora Network",
      link: "/zora-network/intro",
      match: "/zora-network",
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
        text: "NFT Smart Contracts",
        items: [
          {
            text: "Introduction",
            link: "/contracts/intro",
          },
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
                link: "/contracts/metadata",
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
        ],
      },
    ],
    "/protocol-sdk": [
      {
        text: "Protocol SDKs",
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
                text: "create 1155s gaslessly (premints)",
                link: "/protocol-sdk/creator/premint",
              },
              {
                text: "create 1155s onchain",
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
                text: "get an 1155, 721, or premint",
                link: "/protocol-sdk/collect/get",
              },
              {
                text: "getting tokens of an 1155 contract",
                link: "/protocol-sdk/collect/get-of-contract",
              },
              {
                text: "mint",
                link: "/protocol-sdk/collect/mint",
              },
              {
                text: "get mint costs",
                link: "/protocol-sdk/collect/mint-costs",
              },
            ],
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
    esbuild: {
      supported: {
        "top-level-await": true, //browsers can handle top-level-await features
      },
    },
  },
});
