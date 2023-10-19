import { defineConfig } from 'tsup'

export default defineConfig({
  entry: ['package/index.ts', 'package/premint-api.ts'],
  sourcemap: true,
  clean: true,
  dts: false,
  format: ['cjs'],
  onSuccess: 'tsc --emitDeclarationOnly --declaration --declarationMap'
})