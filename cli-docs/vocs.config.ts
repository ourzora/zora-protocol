import { defineConfig } from "vocs";
import { Fragment, createElement } from "react";

const OG_IMAGE = "/og.png";

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
  // The landing page uses `motion` + `@number-flow/react`. Pre-bundle them so
  // Vite links their `react` import to the same optimized React chunk Vocs
  // uses, and dedupe React/React-DOM so there is only ever one copy at runtime
  // (otherwise motion's `useReducedMotion` reads a null React → invalid hook
  // call). Vocs merges this `vite` block into its own config.
  vite: {
    resolve: {
      dedupe: ["react", "react-dom"],
    },
    optimizeDeps: {
      include: ["motion", "motion/react", "@number-flow/react"],
    },
  },
  title: "Agents on Zora",
  titleTemplate: "%s — Agents on Zora",
  logoUrl: "/zorb.svg",
  iconUrl: "/zorb.svg",
  description:
    "One prompt to set up your agent with a profile, wallet, and social network.",
  ogImageUrl: { "/": OG_IMAGE },
  head: () =>
    createElement(
      Fragment,
      null,
      createElement("meta", { property: "og:image:width", content: "2400" }),
      createElement("meta", { property: "og:image:height", content: "1280" }),
    ),
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
        {
          text: "get",
          link: "/commands/get",
          items: [
            {
              text: "get price-history",
              link: "/commands/get#get-price-history",
            },
            { text: "get trades", link: "/commands/get#get-trades" },
            { text: "get holders", link: "/commands/get#get-holders" },
          ],
        },
        { text: "buy", link: "/commands/buy" },
        { text: "sell", link: "/commands/sell" },
        { text: "send", link: "/commands/send" },
        { text: "comment", link: "/commands/comment" },
        { text: "create", link: "/commands/create" },
        { text: "balance", link: "/commands/balance" },
        {
          text: "profile",
          link: "/commands/profile",
          items: [
            { text: "profile posts", link: "/commands/profile#profile-posts" },
            {
              text: "profile holdings",
              link: "/commands/profile#profile-holdings",
            },
            {
              text: "profile trades",
              link: "/commands/profile#profile-trades",
            },
          ],
        },
        { text: "auth", link: "/commands/auth" },
        { text: "setup", link: "/commands/setup" },
        { text: "wallet", link: "/commands/wallet" },
        {
          text: "agent",
          link: "/commands/agent",
          items: [
            { text: "agent create", link: "/commands/agent#agent-create" },
            { text: "agent coin", link: "/commands/agent#agent-coin" },
            {
              text: "agent connect-email",
              link: "/commands/agent#agent-connect-email",
            },
            { text: "agent update", link: "/commands/agent#agent-update" },
          ],
        },
        { text: "dm", link: "/commands/dm" },
        { text: "follow", link: "/commands/follow" },
        { text: "skills", link: "/commands/skills" },
      ],
    },
    {
      text: "Guides",
      collapsed: false,
      items: [
        { text: "JSON Mode & Scripting", link: "/guides/json-mode" },
        { text: "Configuration", link: "/guides/configuration" },
        { text: "Wallet Modes", link: "/guides/wallet-modes" },
        { text: "Skills", link: "/guides/agent-skills" },
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
