import { rm } from "node:fs/promises";
import path from "node:path";
import { defineConfig } from "vite";
import type { Plugin, UserConfig } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";
import type { InlineConfig } from "vitest";

// marks the browser tab when the dev server is serving the app, so a development tab
// isn't mistaken for a production one. apply: "serve" leaves `vite build` untouched
function developmentTab(): Plugin {
  return {
    name: "development-tab",
    apply: "serve",
    transformIndexHtml(html) {
      return (
        html
          .replace(
            "<title>Tribune</title>",
            "<title>Tribune (Development)</title>",
          )
          .replaceAll("/favicon/", "/favicon-dev/")
          // the development icon is red, which reads on a light or a dark tab
          // bar, so there's no dark variant to point the rewrite at. dropping
          // the attribute leaves the runtime swap in index.html with nothing
          // to do rather than pointing it at a file that doesn't exist
          .replaceAll(/\s*data-dark-href="[^"]*"/g, "")
      );
    },
  };
}

// vite copies everything in publicDir into the build, so the development icons
// would otherwise ship to production as dead weight. nothing references them
// there - the title and favicon rewrite above only runs on the dev server
function dropDevelopmentFavicon(): Plugin {
  let outDir = "";
  return {
    name: "drop-development-favicon",
    apply: "build",
    configResolved(resolved) {
      outDir = path.resolve(resolved.root, resolved.build.outDir);
    },
    async closeBundle() {
      await rm(path.join(outDir, "favicon-dev"), {
        recursive: true,
        force: true,
      });
    },
  };
}

// https://vite.dev/config/
type ViteConfig = UserConfig & { test: InlineConfig };
const config: ViteConfig = {
  plugins: [
    react(),
    developmentTab(),
    dropDevelopmentFavicon(),
    VitePWA({
      registerType: "autoUpdate",
      workbox: {
        globPatterns: ["**/*.{js,css,html,ico,png,svg}"],
        // the development favicon is only ever served by the dev server
        globIgnores: ["favicon-dev/**"],
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
