import { defineConfig } from "@hey-api/openapi-ts";

export default defineConfig({
  input: "https://api-sdk.zora.engineering/openapi",
  output: {
    path: "src/client",
    format: "prettier",
  },
  plugins: ["@hey-api/client-fetch"],
});
