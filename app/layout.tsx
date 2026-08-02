import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "ROZZA — pull sound from anywhere",
  description: "A browser-based audio deck for links, streams, and local files.",
  manifest: "/manifest.webmanifest",
  appleWebApp: {
    capable: true,
    statusBarStyle: "black-translucent",
    title: "ROZZA",
  },
};

export const viewport: Viewport = {
  themeColor: "#1c0c12",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
