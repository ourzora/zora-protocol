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
      text: "SDK",
      items: [
        {
          text: "Getting Started",
          link: "/protocol-sdk/getting-started",
        },
        {
          text: "Collect Onchain 1155 Tokens",
          link: "/protocol-sdk/mint-client",
        },
        {
          text: "Create Onchain 1155 Tokens",
          link: "/protocol-sdk/1155-creator-client",
        },
        {
          text: "Gasslessly Create 1155 Tokens (Premint)",
          link: "/protocol-sdk/premint-client",
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
