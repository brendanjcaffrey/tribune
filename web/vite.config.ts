import { defineConfig } from "vite";
import type { UserConfig } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";
import type { InlineConfig } from "vitest";

// https://vite.dev/config/
type ViteConfig = UserConfig & { test: InlineConfig };
const config: ViteConfig = {
  plugins: [
    react(),
    VitePWA({
      registerType: "autoUpdate",
      workbox: {
        globPatterns: ["**/*.{js,css,html,ico,png,svg}"],
      },
      manifest: {
        name: "Tribune",
        short_name: "Tribune",
        description: "Tribune newsletter platform",
        theme_color: "#ffffff",
        icons: [
          {
            src: "favicon/android-chrome-192x192.png",
            sizes: "192x192",
            type: "image/png",
          },
          {
            src: "favicon/android-chrome-512x512.png",
            sizes: "512x512",
            type: "image/png",
          },
        ],
      },
    }),
  ],
  build: {
    outDir: "../public",
    emptyOutDir: true,
  },
  test: {
    environment: "jsdom",
  },
  server: {
    port: 1848,
    // allowedHosts: true, // uncomment this line if you want to allow remote access
    proxy: {
      "/users": "http://localhost:1847",
      "/auth": "http://localhost:1847",
      "/newsletters": "http://localhost:1847",
    },
  },
};

export default defineConfig(config);
