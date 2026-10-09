import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { env } from "./http.ts";

export function adminClient(): SupabaseClient {
  return createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function bearerToken(req: Request): string | null {
  const value = req.headers.get("authorization");
  if (!value?.toLowerCase().startsWith("bearer ")) return null;
  return value.slice(7).trim() || null;
}

export async function requireUser(req: Request, client: SupabaseClient): Promise<string> {
  const token = bearerToken(req);
  if (!token) throw new Error("Authentication required");
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user) throw new Error("Invalid or expired authentication token");
  return data.user.id;
}

export async function requireWorkspaceRole(
  client: SupabaseClient,
  userId: string,
  workspaceId: string,
  roles: string[],
): Promise<void> {
  const { data, error } = await client
    .from("workspace_members")
    .select("role")
    .eq("workspace_id", workspaceId)
    .eq("user_id", userId)
    .maybeSingle();
  if (error || !data || !roles.includes(data.role)) throw new Error("Workspace access denied");
}
