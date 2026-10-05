import { defineConfig } from 'vite';

// Relative base so the build works both locally and on GitHub Pages (/a35-racer/).
export default defineConfig({
  base: './',
  build: { target: 'es2022', chunkSizeWarningLimit: 1500 },
});
