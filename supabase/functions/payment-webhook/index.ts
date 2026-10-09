import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient } from "../_shared/client.ts";
import { verifyHmacSha256Hex } from "../_shared/crypto.ts";
import { env, errorMessage, json } from "../_shared/http.ts";

type LemonPayload = {
  meta?: { event_name?: string; custom_data?: Record<string, unknown> };
  data?: { id?: string | number; attributes?: Record<string, any> };
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const rawBody = await req.text();
  const signature = req.headers.get("x-signature") ?? "";
  const allowTest = Deno.env.get("ALLOW_TEST_WEBHOOKS") === "true";
  const isTest = req.headers.get("x-test-webhook") === "true";
  let signatureValid = false;

  try {
    signatureValid = allowTest && isTest
      ? true
      : await verifyHmacSha256Hex(rawBody, signature, env("LEMON_SQUEEZY_WEBHOOK_SECRET"));
    if (!signatureValid) return json({ error: "Invalid signature" }, 401);
  } catch (error) {
    return json({ error: errorMessage(error) }, 500);
  }

  let payload: LemonPayload;
  try {
    payload = JSON.parse(rawBody) as LemonPayload;
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const client = adminClient();
  const eventType = String(payload.meta?.event_name ?? "unknown");
  const externalOrderId = String(payload.data?.id ?? "");
  const providerEventId = req.headers.get("x-event-id") ?? `${externalOrderId}:${eventType}`;
  const attrs = payload.data?.attributes ?? {};

  const { data: event, error: eventError } = await client.from("webhook_events").insert({
    provider: "lemon_squeezy",
    provider_event_id: providerEventId,
    event_type: eventType,
    signature_valid: signatureValid,
    payload,
  }).select("id").single();

  if (eventError?.code === "23505") return json({ accepted: true, idempotent_replay: true }, 200);
  if (eventError || !event) return json({ error: eventError?.message ?? "Could not record event" }, 500);

  if (eventType !== "order_created") {
    await client.from("webhook_events").update({ status: "ignored", processed_at: new Date().toISOString() }).eq("id", event.id);
    return json({ accepted: true, ignored: true }, 202);
  }

  try {
    const custom = payload.meta?.custom_data ?? {};
    const item = attrs.first_order_item ?? {};
    const { data, error } = await client.rpc("ingest_paid_order", {
      p_provider: "lemon_squeezy",
      p_external_order_id: externalOrderId,
      p_external_customer_id: attrs.customer_id ? String(attrs.customer_id) : null,
      p_customer_email: attrs.user_email ?? attrs.customer_email,
      p_customer_name: attrs.user_name ?? attrs.customer_name ?? null,
      p_product_sku: custom.product_sku ? String(custom.product_sku) : null,
      p_external_product_id: item.variant_id ? String(item.variant_id) : item.product_id ? String(item.product_id) : null,
      p_currency: String(attrs.currency ?? "USD").toUpperCase(),
      p_gross_minor: Number(attrs.total ?? attrs.subtotal ?? 0),
      p_net_minor: attrs.total_usd != null ? Number(attrs.total_usd) : null,
      p_license_type: custom.license_type ? String(custom.license_type) : "individual",
      p_provider_payload: payload,
    });
    if (error) throw error;
    await client.from("webhook_events").update({ status: "processed", processed_at: new Date().toISOString() }).eq("id", event.id);
    return json({ accepted: true, result: data }, 202);
  } catch (error) {
    await client.from("webhook_events").update({ status: "failed", error_message: errorMessage(error).slice(0, 1000) }).eq("id", event.id);
    return json({ error: "Order ingestion failed", detail: errorMessage(error) }, 422);
  }
});
