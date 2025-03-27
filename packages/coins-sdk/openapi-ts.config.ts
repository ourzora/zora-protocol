import { defineConfig } from "@hey-api/openapi-ts";

export default defineConfig({
  input: "https://api-sdk.zora.engineering/openapi",
  output: "src/client",
  plugins: ["@hey-api/client-fetch"],
});
