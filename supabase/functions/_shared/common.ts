import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  authenticatedUserId,
  enforceRateLimit,
  requirePremiumEntitlement,
} from "./auth.ts";

export const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

export const preflight = (request: Request) =>
  request.method === "OPTIONS"
    ? new Response(null, { status: 204, headers: cors })
    : null;

type AdminClient = ReturnType<typeof createClient<any>>;

type AuthContext = {
  admin: AdminClient;
  uid: string;
};

export async function authenticate(
  request: Request,
): Promise<AuthContext | Response> {
  const uid = await authenticatedUserId(request);
  if (uid instanceof Response) return uid;

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("Supabase service-role environment is not configured.");
    return reply({ error: "API is not configured" }, 503);
  }

  return {
    uid,
    admin: createClient<any>(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    }),
  };
}

export function enforceRequestLimit(
  userId: string,
  bucket: string,
  limit: number,
  windowSeconds = 600,
) {
  return enforceRateLimit(userId, bucket, limit, windowSeconds);
}

export function requirePremium(userId: string) {
  return requirePremiumEntitlement(userId);
}

export async function gbif(path: string) {
  const response = await fetch(`https://api.gbif.org/v1/${path}`, {
    signal: AbortSignal.timeout(12_000),
  });
  if (!response.ok) throw new Error(`GBIF HTTP ${response.status}`);
  return await response.json();
}
