import { defineConfig } from 'tsdown';

export default defineConfig({
  dts: true,
  exports: true,
  entry: ['src/index.ts'],
  clean: true,
  sourcemap: true,
  outputOptions: {
    comments: false,
  },
});
