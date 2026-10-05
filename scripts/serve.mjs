// Starts Next bound to 127.0.0.1 by default. Binding anywhere else (HOST=0.0.0.0, a LAN IP...)
// is refused until an owner password exists, so the app is never reachable from the network unprotected.
import { spawn } from "node:child_process";
import { chmodSync, existsSync, readdirSync } from "node:fs";
import { PrismaClient } from "@prisma/client";

if (existsSync(".env")) process.loadEnvFile(".env");

// Owner-only database files (tasks, sessions, account email).
for (const f of existsSync("prisma") ? readdirSync("prisma") : []) {
  if (/\.db(-journal|-wal|-shm)?$|\.bak$/.test(f)) chmodSync(`prisma/${f}`, 0o600);
}

const mode = process.argv[2] === "start" ? "start" : "dev";
const host = process.env.HOST || "127.0.0.1";
const port = process.env.PORT || "3000";
const loopback = ["127.0.0.1", "localhost", "::1"].includes(host) || /^127\./.test(host);

if (!loopback) {
  const prisma = new PrismaClient();
  const hasPassword = (await prisma.authConfig.count().catch(() => 0)) > 0;
  await prisma.$disconnect();
  if (!hasPassword) {
    console.error(
      `Refusing to listen on ${host}: no password is set yet.\n` +
        "Start once on localhost (npm run dev), open http://localhost:" + port + " and set a password, then try again.",
    );
    process.exit(1);
  }
  if (!process.env.PUBLIC_HOSTS) {
    console.error("Set PUBLIC_HOSTS to the hostname(s) you will use, and put ProTask behind HTTPS (see the README).");
    process.exit(1);
  }
  console.warn(`Listening on ${host}. Requests from other machines are only accepted over HTTPS.`);
}

const next = spawn("npx", ["next", mode, "-H", host, "-p", port], { stdio: "inherit" });
next.on("exit", (code) => process.exit(code ?? 0));
for (const sig of ["SIGINT", "SIGTERM"]) process.on(sig, () => next.kill(sig));
