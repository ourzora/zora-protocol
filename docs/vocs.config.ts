import { defineConfig } from "vocs";

export default defineConfig({
  title: "Zora Developer Tools",
  titleTemplate: "%s – Zora Developer Tools",
  iconUrl: "/zoraOrb.svg",
  basePath: process.env.BASE_PATH,
  rootDir: ".",
  topNav: [
    {
      text: "Protocol Deployments Package",
      link: "/protocol-deployments/guide",
      match: "/protocol-deployments",
    },
    {
      text: "SDK",
      link: "/protocol-sdk/getting-started",
      match: "/protocol-sdk",
    },
  ],
  socials: [
    {
      icon: "github",
      link: "https://github.com/ourzora/zora-protocol",
    },
  ],
  sidebar: [
    {
      text: "Introduction",
      link: "/",
    },
    {
      text: "Protocol Deployments Package",
      items: [
        {
          text: "Usage",
          link: "/protocol-deployments/guide",
        },
      ],
    },
    {
      text: "Protocol SDK",
      items: [
        {
          text: "Introduction",
          link: "/protocol-sdk/introduction",
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
          text: "Collector Client",
          items: [
            {
              text: "mint",
              link: "/protocol-sdk/collect/mint",
            },
            {
              text: "getMintCosts",
              link: "/protocol-sdk/collect/mint-costs",
            },
          ],
        },
      ],
    },
  ],
  vite: {
    esbuild: {
      supported: {
        "top-level-await": true, //browsers can handle top-level-await features
      },
    },
  },
});
