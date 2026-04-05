import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const tests = [
  path.join(__dirname, "lib", "utils.test.js"),
  path.join(__dirname, "hooks", "session-hooks.test.js"),
];

let failed = 0;
for (const t of tests) {
  const name = path.relative(__dirname, t);
  try {
    execFileSync(process.execPath, [t], { stdio: "inherit" });
    console.log(`  PASS  ${name}`);
  } catch {
    console.error(`  FAIL  ${name}`);
    failed++;
  }
}

process.exit(failed > 0 ? 1 : 0);
