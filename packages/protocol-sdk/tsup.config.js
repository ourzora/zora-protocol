import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["src/index.ts"],
  sourcemap: true,
  clean: true,
  dts: false,
  format: ["cjs", "esm"],
  onSuccess: "tsc --project tsconfig.types.json --emitDeclarationOnly --declaration --declarationMap",
});
