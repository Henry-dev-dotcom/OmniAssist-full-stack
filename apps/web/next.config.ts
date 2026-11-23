import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  async headers() {
    return [
      {
        source: "/sw.js",
        headers: [{ key: "Cache-Control", value: "no-cache, no-store, must-revalidate" }],
      },
    ];
  },
  cacheComponents: true,
  experimental: {
    // Vercel restores .next/cache before each build. With the Turbopack build cache on, a deploy
    // shipped the new JavaScript with the previous build's stylesheet (globals.css changes, run
    // through the Tailwind loader, were not picked up). Builds compile from scratch instead.
    turbopackFileSystemCacheForBuild: false,
  },
  partialPrefetching: true,
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
