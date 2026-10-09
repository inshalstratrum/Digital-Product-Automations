import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { adminClient, requireUser, requireWorkspaceRole } from "../_shared/client.ts";
import { cors, errorMessage, json, readJson } from "../_shared/http.ts";

type IdeaInput = {
  workspace_id: string;
  niche: string;
  angle: string;
  audience?: string;
  evidence_note?: string;
  source_url?: string;
  metrics: { demand: number; competition: number; feasibility: number; founder_fit: number; evidence_quality: number };
};

Deno.serve(async (req) => {
  const headers = cors(req);
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, headers);
  try {
    const client = adminClient();
    const userId = await requireUser(req, client);
    const input = await readJson<IdeaInput>(req);
    await requireWorkspaceRole(client, userId, input.workspace_id, ["owner", "admin", "operator"]);
    if (!input.niche?.trim() || !input.angle?.trim()) return json({ error: "niche and angle are required" }, 400, headers);
    const metrics = input.metrics ?? ({} as IdeaInput["metrics"]);
    for (const key of ["demand", "competition", "feasibility", "founder_fit", "evidence_quality"] as const) {
      if (!Number.isFinite(Number(metrics[key])) || Number(metrics[key]) < 0 || Number(metrics[key]) > 100) {
        return json({ error: `${key} must be between 0 and 100` }, 400, headers);
      }
    }
    const { data, error } = await client.from("content_ideas").insert({
      workspace_id: input.workspace_id,
      submitted_by: userId,
      niche: input.niche.trim(),
      angle: input.angle.trim(),
      audience: input.audience?.trim() || null,
      evidence_note: input.evidence_note?.trim() || null,
      source_url: input.source_url?.trim() || null,
      metrics,
    }).select("id,status").single();
    if (error) throw error;
    return json({ accepted: true, idea: data }, 202, headers);
  } catch (error) {
    const message = errorMessage(error);
    const status = /Authentication|token/.test(message) ? 401 : /access denied/.test(message) ? 403 : 400;
    return json({ error: message }, status, headers);
  }
});
