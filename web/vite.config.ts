import { defineConfig } from "vite";
import type { UserConfig } from "vite";
import react from "@vitejs/plugin-react";
import type { InlineConfig } from "vitest";

// https://vite.dev/config/
type ViteConfig = UserConfig & { test: InlineConfig };
const config: ViteConfig = {
  plugins: [react()],
  build: {
    outDir: "../public",
    emptyOutDir: true,
  },
  test: {
    environment: "jsdom",
  },
  server: {
    port: 1848,
    proxy: {
      "/users": "http://localhost:1847",
      "/auth": "http://localhost:1847",
      "/newsletters": "http://localhost:1847",
    },
  },
};

export default defineConfig(config);
