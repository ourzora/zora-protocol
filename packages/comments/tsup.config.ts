import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["package/index.ts"],
  sourcemap: true,
  clean: true,
  dts: false,
  format: ["cjs", "esm"],
  onSuccess:
    "tsc --project tsconfig.build.json  --emitDeclarationOnly --declaration --declarationMap",
});
