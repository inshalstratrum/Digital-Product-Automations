import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import { adminClient } from "../_shared/client.ts";
import { safeEqual } from "../_shared/crypto.ts";
import {
  deterministicFeedbackClassification,
  deterministicIdeaScore,
} from "../_shared/intelligence.ts";
import { env, errorMessage, json } from "../_shared/http.ts";

type QueueName = "sales_fulfillment" | "idea_scoring" | "feedback_classification";
type QueueMessage = {
  msg_id: number;
  read_ct: number;
  enqueued_at: string;
  vt: string;
  message: Record<string, unknown>;
};

async function updateRun(client: SupabaseClient, runId: unknown, values: Record<string, unknown>) {
  if (!runId) return;
  const { error } = await client.from("automation_runs").update(values).eq("id", String(runId));
  if (error) throw error;
}

async function processSales(client: SupabaseClient, message: QueueMessage) {
  const orderId = String(message.message.order_id ?? "");
  const runId = message.message.run_id;
  await updateRun(client, runId, { status: "running", started_at: new Date().toISOString(), attempt: message.read_ct });
  const { data: order, error: orderError } = await client
    .from("orders")
    .select("id,workspace_id,customer_id,feedback_token,customer:customers(email,name)")
    .eq("id", orderId)
    .single();
  if (orderError || !order) throw orderError ?? new Error("Order not found");

  const { data: items, error: itemsError } = await client
    .from("order_items")
    .select("id,product_id,product_version_id,product:products(name,sku)")
    .eq("order_id", orderId);
  if (itemsError || !items?.length) throw itemsError ?? new Error("Order has no items");

  const deliverables: Array<{ asset_id: string; label: string; bucket_id: string; object_path: string }> = [];
  for (const item of items) {
    if (!item.product_version_id) continue;
    const { data: assets, error: assetError } = await client
      .from("product_assets")
      .select("id,bucket_id,object_path,label")
      .eq("product_version_id", item.product_version_id)
      .in("asset_type", ["download", "guide", "license"])
      .order("sort_order");
    if (assetError) throw assetError;
    for (const asset of assets ?? []) deliverables.push({
      asset_id: asset.id,
      label: asset.label,
      bucket_id: asset.bucket_id,
      object_path: asset.object_path,
    });
  }
  if (!deliverables.length) throw new Error("No deliverable assets are configured for this product version");

  const customer = order.customer as unknown as { email: string; name?: string | null };
  const productNames = items.map((item: any) => item.product?.name ?? item.product?.sku ?? "Digital product");
  const { error: outboundError } = await client.from("outbound_messages").insert({
    workspace_id: order.workspace_id,
    customer_id: order.customer_id,
    recipient: customer.email,
    template_key: "order_delivery",
    payload: {
      customer_name: customer.name,
      order_id: order.id,
      products: productNames,
      deliverables,
      feedback_token: order.feedback_token,
    },
  });
  if (outboundError) throw outboundError;
  await updateRun(client, runId, {
    status: "succeeded",
    output: { queued_delivery_email: true, deliverable_count: deliverables.length },
    finished_at: new Date().toISOString(),
  });
}

async function processIdea(client: SupabaseClient, message: QueueMessage) {
  const ideaId = String(message.message.idea_id ?? "");
  const runId = message.message.run_id;
  await updateRun(client, runId, { status: "running", started_at: new Date().toISOString(), attempt: message.read_ct });
  const { data: idea, error } = await client.from("content_ideas").select("*").eq("id", ideaId).single();
  if (error || !idea) throw error ?? new Error("Idea not found");
  const result = deterministicIdeaScore(idea.metrics ?? {});
  const score = Math.max(0, Math.min(100, Number(result.score)));
  const status = score >= 70 ? "review" : "low_priority";
  const { error: updateError } = await client.from("content_ideas").update({
    score,
    score_breakdown: { ...result.breakdown, method: result.method },
    status,
  }).eq("id", ideaId);
  if (updateError) throw updateError;
  if (status === "review") {
    const { error: approvalError } = await client.from("approval_requests").insert({
      workspace_id: idea.workspace_id,
      request_type: "idea",
      entity_id: idea.id,
      summary: `Review product idea (${score}/100): ${idea.angle}`,
      requested_by: idea.submitted_by,
    });
    if (approvalError && approvalError.code !== "23505") throw approvalError;
  }
  await updateRun(client, runId, {
    status: status === "review" ? "waiting_approval" : "succeeded",
    output: { score, decision: status, method: result.method },
    finished_at: new Date().toISOString(),
  });
}

async function processFeedback(client: SupabaseClient, message: QueueMessage) {
  const feedbackId = String(message.message.feedback_id ?? "");
  const runId = message.message.run_id;
  await updateRun(client, runId, { status: "running", started_at: new Date().toISOString(), attempt: message.read_ct });
  const { data: feedback, error } = await client.from("customer_feedback").select("*").eq("id", feedbackId).single();
  if (error || !feedback) throw error ?? new Error("Feedback not found");
  const result = deterministicFeedbackClassification(feedback.note, feedback.rating);
  const needsAction = result.severity === "high" || result.severity === "critical";
  const { error: updateError } = await client.from("customer_feedback").update({
    issue_type: result.issue_type,
    severity: result.severity,
    sentiment: Math.max(-1, Math.min(1, Number(result.sentiment))),
    tags: result.tags,
    classification: { method: result.method },
    status: needsAction ? "needs_action" : "acknowledged",
  }).eq("id", feedbackId);
  if (updateError) throw updateError;

  if (needsAction) {
    const { data: change, error: changeError } = await client.from("change_requests").insert({
      workspace_id: feedback.workspace_id,
      product_id: feedback.product_id,
      title: `${result.issue_type}: customer feedback requires review`,
      description: feedback.note,
      source: "feedback",
      priority: result.severity,
    }).select("id").single();
    if (changeError) throw changeError;
    const { error: approvalError } = await client.from("approval_requests").insert({
      workspace_id: feedback.workspace_id,
      request_type: "customer_issue",
      entity_id: feedback.id,
      summary: `${result.severity.toUpperCase()} ${result.issue_type}: ${feedback.note.slice(0, 180)}`,
    });
    if (approvalError && approvalError.code !== "23505") throw approvalError;
    await updateRun(client, runId, {
      status: "waiting_approval",
      output: { classification: result, change_request_id: change.id },
      finished_at: new Date().toISOString(),
    });
    return;
  }
  await updateRun(client, runId, {
    status: "succeeded",
    output: { classification: result },
    finished_at: new Date().toISOString(),
  });
}

async function processMessage(client: SupabaseClient, queue: QueueName, message: QueueMessage) {
  if (queue === "sales_fulfillment") return processSales(client, message);
  if (queue === "idea_scoring") return processIdea(client, message);
  return processFeedback(client, message);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const suppliedSecret = req.headers.get("x-worker-secret") ?? "";
  if (!safeEqual(suppliedSecret, env("WORKER_SECRET"))) return json({ error: "Unauthorized" }, 401);
  const client = adminClient();
  const queues: QueueName[] = ["sales_fulfillment", "idea_scoring", "feedback_classification"];
  const summary: Record<string, { claimed: number; succeeded: number; failed: number; dead_lettered: number }> = {};

  for (const queue of queues) {
    summary[queue] = { claimed: 0, succeeded: 0, failed: 0, dead_lettered: 0 };
    const { data, error } = await client.rpc("claim_automation_jobs", {
      p_queue: queue,
      p_visibility_seconds: 180,
      p_batch_size: 5,
    });
    if (error) return json({ error: `Could not claim ${queue}: ${error.message}` }, 500);
    const messages = (data ?? []) as QueueMessage[];
    summary[queue].claimed = messages.length;
    for (const message of messages) {
      try {
        await processMessage(client, queue, message);
        const { error: completeError } = await client.rpc("complete_automation_job", {
          p_queue: queue,
          p_msg_id: message.msg_id,
          p_archive: true,
        });
        if (completeError) throw completeError;
        summary[queue].succeeded += 1;
      } catch (error) {
        summary[queue].failed += 1;
        const runId = message.message.run_id;
        const deadLetter = message.read_ct >= 5;
        await updateRun(client, runId, {
          status: deadLetter ? "dead_letter" : "failed",
          attempt: message.read_ct,
          error_message: errorMessage(error).slice(0, 1000),
          finished_at: new Date().toISOString(),
        }).catch(() => undefined);
        if (deadLetter) {
          await client.rpc("complete_automation_job", { p_queue: queue, p_msg_id: message.msg_id, p_archive: true });
          summary[queue].dead_lettered += 1;
        }
      }
    }
  }
  return json({ ok: true, summary });
});
