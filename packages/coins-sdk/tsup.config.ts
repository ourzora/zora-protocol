import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["src/index.ts"],
  sourcemap: true,
  clean: true,
  dts: false,
  splitting: true,
  format: ["cjs", "esm"],
  tsconfig: "tsconfig.build.json",
  onSuccess:
    "tsc --project tsconfig.build.json --emitDeclarationOnly --declaration --declarationMap",
});
