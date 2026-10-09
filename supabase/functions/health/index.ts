import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient } from "../_shared/client.ts";
import { json } from "../_shared/http.ts";

Deno.serve(async () => {
  const client = adminClient();
  const { error } = await client.from("products").select("id", { count: "exact", head: true }).limit(1);
  return error
    ? json({ ok: false, database: "unavailable" }, 503)
    : json({ ok: true, database: "available", checked_at: new Date().toISOString() });
});
