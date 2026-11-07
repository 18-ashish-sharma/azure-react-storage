import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Output goes to dist/, which is uploaded as-is to the storage account's $web container.
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist',
    sourcemap: false
  }
});
