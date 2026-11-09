import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jsonResponse } from "./http.ts";

function serviceClient() {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("Supabase service-role environment is not configured.");
    return null;
  }

  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export async function authenticatedUserId(
  request: Request,
): Promise<string | Response> {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return jsonResponse({ error: { code: "authentication_required" } }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !anonKey) {
    console.error("Supabase authentication environment is not configured.");
    return jsonResponse({ error: { code: "function_not_configured" } }, 503);
  }

  const token = authorization.slice("Bearer ".length);
  const supabase = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) {
    return jsonResponse({ error: { code: "invalid_session" } }, 401);
  }
  if (!data.user.email_confirmed_at) {
    return jsonResponse({ error: { code: "email_verification_required" } }, 403);
  }

  return data.user.id;
}

export async function enforceRateLimit(
  userId: string,
  bucket: string,
  limit: number,
  windowSeconds: number,
): Promise<Response | null> {
  const supabase = serviceClient();
  if (!supabase) {
    return jsonResponse({ error: { code: "function_not_configured" } }, 503);
  }

  const { data, error } = await supabase.rpc("consume_api_rate_limit", {
    p_user_id: userId,
    p_bucket: bucket,
    p_limit: limit,
    p_window_seconds: windowSeconds,
  });
  if (error) {
    console.error("Rate limit check failed:", error.code);
    return jsonResponse({ error: { code: "rate_limit_unavailable" } }, 503);
  }
  if (data !== true) {
    return jsonResponse(
      { error: { code: "rate_limit_exceeded" } },
      429,
    );
  }

  return null;
}

export async function requirePremiumEntitlement(
  userId: string,
): Promise<Response | null> {
  const supabase = serviceClient();
  if (!supabase) {
    return jsonResponse({ error: { code: "function_not_configured" } }, 503);
  }

  const { data, error } = await supabase
    .from("subscription_entitlements")
    .select("user_id")
    .eq("user_id", userId)
    .eq("status", "active")
    .gt("expires_at", new Date().toISOString())
    .limit(1)
    .maybeSingle();

  if (error) {
    console.error("Premium entitlement check failed:", error.code);
    return jsonResponse(
      { error: { code: "entitlement_check_unavailable" } },
      503,
    );
  }
  if (!data) {
    return jsonResponse(
      { error: { code: "premium_entitlement_required" } },
      403,
    );
  }

  return null;
}
