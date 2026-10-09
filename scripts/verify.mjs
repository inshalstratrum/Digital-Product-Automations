import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";

const root = new URL("../", import.meta.url);
const required = [
  "supabase/config.toml",
  "supabase/seed.sql",
  "supabase/functions/payment-webhook/index.ts",
  "supabase/functions/submit-idea/index.ts",
  "supabase/functions/submit-feedback/index.ts",
  "supabase/functions/automation-worker/index.ts",
  "supabase/functions/health/index.ts",
];
const failures = [];

for (const relative of required) {
  try {
    const data = await readFile(new URL(relative, root), "utf8");
    if (!data.trim()) failures.push(`${relative} is empty`);
  } catch {
    failures.push(`${relative} is missing`);
  }
}

const migrations = await readdir(new URL("supabase/migrations/", root));
if (migrations.filter((name) => name.endsWith(".sql")).length < 2) {
  failures.push("Expected the core and hardening SQL migrations");
}

if (failures.length) {
  console.error(failures.join("\n"));
  process.exit(1);
}
console.log(`Verified ${required.length} required files and ${migrations.length} migrations.`);
