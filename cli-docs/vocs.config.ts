import { defineConfig } from "vocs";

const zoraLight = {
  name: "zora-light",
  type: "light" as const,
  colors: {
    "editor.background": "#f5f5f5",
    "editor.foreground": "#1a1a1a",
  },
  tokenColors: [
    {
      scope: [
        "keyword",
        "storage",
        "storage.type",
        "keyword.control",
        "keyword.operator.new",
        "keyword.operator.expression",
        "keyword.operator.typeof",
      ],
      settings: { foreground: "#00df00" },
    },
    {
      scope: ["string", "string.quoted"],
      settings: { foreground: "#ff00f0" },
    },
    {
      scope: ["comment", "comment.line", "comment.block"],
      settings: { foreground: "#b5b5b5" },
    },
    {
      scope: ["entity.name.function", "support.function"],
      settings: { foreground: "#1a1a1a" },
    },
    {
      scope: ["constant.numeric", "constant.language"],
      settings: { foreground: "#00df00" },
    },
    {
      scope: [
        "entity.name.type",
        "support.type",
        "entity.name.class",
        "entity.name.tag",
      ],
      settings: { foreground: "#ff00f0" },
    },
    {
      scope: ["keyword.operator"],
      settings: { foreground: "#999999" },
    },
    {
      scope: ["punctuation"],
      settings: { foreground: "#878787" },
    },
    {
      scope: [
        "variable",
        "variable.other",
        "variable.other.property",
        "meta.object-literal.key",
      ],
      settings: { foreground: "#1a1a1a" },
    },
    {
      scope: ["entity.other.attribute-name"],
      settings: { foreground: "#00df00" },
    },
  ],
};

const zoraDark = {
  name: "zora-dark",
  type: "dark" as const,
  colors: {
    "editor.background": "#141414",
    "editor.foreground": "#f3f3f3",
  },
  tokenColors: [
    {
      scope: [
        "keyword",
        "storage",
        "storage.type",
        "keyword.control",
        "keyword.operator.new",
        "keyword.operator.expression",
        "keyword.operator.typeof",
      ],
      settings: { foreground: "#00df00" },
    },
    {
      scope: ["string", "string.quoted"],
      settings: { foreground: "#ff00f0" },
    },
    {
      scope: ["comment", "comment.line", "comment.block"],
      settings: { foreground: "#7a7a7a" },
    },
    {
      scope: ["entity.name.function", "support.function"],
      settings: { foreground: "#f3f3f3" },
    },
    {
      scope: ["constant.numeric", "constant.language"],
      settings: { foreground: "#00df00" },
    },
    {
      scope: [
        "entity.name.type",
        "support.type",
        "entity.name.class",
        "entity.name.tag",
      ],
      settings: { foreground: "#ff00f0" },
    },
    {
      scope: ["keyword.operator"],
      settings: { foreground: "#7a7a7a" },
    },
    {
      scope: ["punctuation"],
      settings: { foreground: "#989898" },
    },
    {
      scope: [
        "variable",
        "variable.other",
        "variable.other.property",
        "meta.object-literal.key",
      ],
      settings: { foreground: "#f3f3f3" },
    },
    {
      scope: ["entity.other.attribute-name"],
      settings: { foreground: "#00df00" },
    },
  ],
};

export default defineConfig({
  title: "Zora CLI",
  titleTemplate: "%s — Zora CLI",
  logoUrl: "/zorb.svg",
  iconUrl: "/zorb.svg",
  description: "Build an AI Agent. Trade Coins.",
  markdown: {
    code: {
      themes: {
        light: zoraLight as any,
        dark: zoraDark as any,
      },
    },
  },
  theme: {
    accentColor: {
      light: "#121212",
      dark: "#f3f3f3",
    },
  },
  llms: {
    generateMarkdown: true,
  },
  topNav: [
    { text: "humans", link: "/getting-started" },
    { text: "agents", link: "/skill" },
    {
      text: "npm",
      link: "https://www.npmjs.com/package/@zoralabs/cli",
    },
    {
      text: "source",
      link: "https://github.com/ourzora/zora-protocol/tree/main/packages/cli",
    },
    {
      text: "zora.co",
      link: "https://zora.co",
    },
  ],
  sidebar: [
    {
      text: "Getting Started",
      link: "/getting-started",
    },
    {
      text: "Agents",
      link: "/skill",
    },
    {
      text: "Commands",
      collapsed: false,
      items: [
        { text: "explore", link: "/commands/explore" },
        { text: "get", link: "/commands/get" },
        { text: "price-history", link: "/commands/price-history" },
        { text: "buy", link: "/commands/buy" },
        { text: "sell", link: "/commands/sell" },
        { text: "send", link: "/commands/send" },
        { text: "balance", link: "/commands/balance" },
        { text: "profile", link: "/commands/profile" },
        { text: "auth", link: "/commands/auth" },
        { text: "setup", link: "/commands/setup" },
        { text: "wallet", link: "/commands/wallet" },
      ],
    },
    {
      text: "Guides",
      collapsed: false,
      items: [
        { text: "AI Agent Integration", link: "/guides/ai-agents" },
        { text: "JSON Mode & Scripting", link: "/guides/json-mode" },
        { text: "Configuration", link: "/guides/configuration" },
      ],
    },
    {
      text: "Reference",
      collapsed: false,
      items: [
        { text: "Global Flags", link: "/reference/global-flags" },
        {
          text: "Environment Variables",
          link: "/reference/environment-variables",
        },
        { text: "Error Handling", link: "/reference/error-handling" },
      ],
    },
  ],
});
