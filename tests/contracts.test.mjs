import test from "node:test";
import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";

const root = new URL("../", import.meta.url);
const migrationName = (await readdir(new URL("supabase/migrations/", root))).find((name) => name.includes("digital_product_automation_core"));
const sql = await readFile(new URL(`supabase/migrations/${migrationName}`, root), "utf8");
const webhook = await readFile(new URL("supabase/functions/payment-webhook/index.ts", root), "utf8");
const worker = await readFile(new URL("supabase/functions/automation-worker/index.ts", root), "utf8");

test("every public business table explicitly enables RLS", () => {
  const tables = [...sql.matchAll(/create table public\.([a-z_]+)/g)].map((match) => match[1]);
  assert.ok(tables.length >= 15);
  for (const table of tables) assert.match(sql, new RegExp(`alter table public\\.${table} enable row level security`));
});

test("trusted RPC functions are not callable by public users", () => {
  for (const name of ["ingest_paid_order", "claim_automation_jobs", "complete_automation_job"]) {
    assert.match(sql, new RegExp(`revoke all on function public\\.${name}`));
    assert.match(sql, new RegExp(`grant execute on function public\\.${name}[^;]+to service_role`, "s"));
  }
});

test("all four durable queues exist and are whitelisted", () => {
  for (const queue of ["sales_fulfillment", "idea_scoring", "feedback_classification", "outbound_email"]) {
    assert.match(sql, new RegExp(`pgmq\\.create\\('${queue}'\\)`));
    assert.match(sql, new RegExp(queue));
  }
});

test("payment intake verifies signatures and handles replay", () => {
  assert.match(webhook, /verifyHmacSha256Hex/);
  assert.match(webhook, /Invalid signature/);
  assert.match(webhook, /23505/);
  assert.match(sql, /unique \(provider, external_order_id\)/);
});

test("worker has bounded retry and dead-letter behavior", () => {
  assert.match(worker, /message\.read_ct >= 5/);
  assert.match(worker, /dead_letter/);
  assert.match(worker, /p_visibility_seconds: 180/);
});

test("authorization does not use user metadata", () => {
  const authorizationSection = sql.slice(
    sql.indexOf("Internal authorization helpers"),
    sql.indexOf("create or replace function private.handle_new_user"),
  );
  assert.doesNotMatch(authorizationSection, /user_meta_data/);
  assert.match(authorizationSection, /workspace_members/);
});
