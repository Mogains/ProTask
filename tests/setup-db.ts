import { execSync } from "node:child_process";
import { rmSync } from "node:fs";
import path from "node:path";

/** Build a fresh throwaway SQLite database for tests (never touches dev.db). */
export default function setup() {
  for (const f of ["test.db", "test.db-journal"]) rmSync(path.join(__dirname, "../prisma", f), { force: true });
  execSync("npx prisma db push --skip-generate", {
    env: { ...process.env, DATABASE_URL: "file:./test.db" },
    stdio: "ignore",
  });
}
