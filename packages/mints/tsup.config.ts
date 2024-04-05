import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["package/index.ts"],
  sourcemap: true,
  clean: true,
  dts: false,
  format: ["cjs", "esm"],
  onSuccess: "tsc --emitDeclarationOnly --declaration --declarationMap",
});
