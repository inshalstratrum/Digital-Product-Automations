import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient } from "../_shared/client.ts";
import { cors, errorMessage, json, readJson } from "../_shared/http.ts";

type FeedbackInput = { feedback_token: string; rating?: number; note: string };

Deno.serve(async (req) => {
  const headers = cors(req);
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, headers);
  try {
    const input = await readJson<FeedbackInput>(req, 20_000);
    if (!input.feedback_token || !input.note?.trim()) return json({ error: "feedback_token and note are required" }, 400, headers);
    if (input.rating != null && (!Number.isInteger(input.rating) || input.rating < 1 || input.rating > 5)) {
      return json({ error: "rating must be an integer from 1 to 5" }, 400, headers);
    }
    const client = adminClient();
    const { data: order, error: orderError } = await client
      .from("orders")
      .select("id,workspace_id,customer_id,order_items(product_id)")
      .eq("feedback_token", input.feedback_token)
      .maybeSingle();
    if (orderError || !order) return json({ error: "Invalid feedback token" }, 404, headers);
    const items = (order.order_items ?? []) as Array<{ product_id: string }>;
    const { data, error } = await client.from("customer_feedback").insert({
      workspace_id: order.workspace_id,
      order_id: order.id,
      customer_id: order.customer_id,
      product_id: items[0]?.product_id ?? null,
      rating: input.rating ?? null,
      note: input.note.trim(),
    }).select("id,status").single();
    if (error) throw error;
    return json({ accepted: true, feedback: data }, 202, headers);
  } catch (error) {
    return json({ error: errorMessage(error) }, 400, headers);
  }
});
