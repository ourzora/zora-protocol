import { defineConfig } from 'tsup'

export default defineConfig({
  entry: ['package/index.ts', 'package/premint-api.ts'],
  sourcemap: true,
  clean: true,
  // dts: true,
  format: ['cjs', 'esm'],
  onSuccess: 'tsc --emitDeclarationOnly --declaration --declarationMap'
})