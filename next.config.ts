import type { NextConfig } from "next";

const devOrigins = (process.env.DEV_ORIGINS ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

const nextConfig: NextConfig = {
  allowedDevOrigins: devOrigins,
  serverExternalPackages: ["googleapis"],
};

export default nextConfig;
