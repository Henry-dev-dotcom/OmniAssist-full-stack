import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import ServiceWorkerRegistration from "./service-worker-registration";
import "./globals.css";

export const metadata: Metadata = {
  applicationName: "OmniAssist",
  title: {
    default: "OmniAssist — Research planner",
    template: "%s — OmniAssist",
  },
  description:
    "A calm, considered workspace for postgraduate research planning and progress.",
  manifest: "/manifest.webmanifest",
  icons: {
    icon: [
      { url: "/icons/icon.svg", type: "image/svg+xml" },
      { url: "/icons/icon-192.png", sizes: "192x192", type: "image/png" },
      { url: "/icons/icon-512.png", sizes: "512x512", type: "image/png" },
    ],
    apple: {
      url: "/icons/apple-touch-icon.png",
      sizes: "180x180",
      type: "image/png",
    },
  },
  appleWebApp: {
    capable: true,
    title: "OmniAssist",
    statusBarStyle: "default",
  },
  formatDetection: {
    address: false,
    email: false,
    telephone: false,
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  colorScheme: "light dark",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#FCFBF7" },
    { media: "(prefers-color-scheme: dark)", color: "#12181F" },
  ],
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <ServiceWorkerRegistration />
        {children}
      </body>
    </html>
  );
}
