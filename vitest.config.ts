import { defineConfig } from "vitest/config";
import path from "node:path";

export default defineConfig({
  resolve: { alias: { "@": path.resolve(__dirname, ".") } },
  test: {
    include: ["tests/**/*.test.ts"],
    // Tests that touch the database use a separate throwaway SQLite file.
    env: { DATABASE_URL: "file:./test.db", GOOGLE_CLIENT_ID: "test-id", GOOGLE_CLIENT_SECRET: "test-secret", TOKEN_STORE: "memory" },
    globalSetup: ["tests/setup-db.ts"],
    fileParallelism: false,
  },
});
