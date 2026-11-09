import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { authenticatedUserId, enforceRateLimit } from "../_shared/auth.ts";
import { corsHeaders, jsonResponse } from "../_shared/http.ts";

type AdminClient = ReturnType<typeof createClient<any>>;

const bucketNames = ["plant-photos", "premium-payment-proofs"];
const pageSize = 100;
const recentAuthenticationWindowSeconds = 5 * 60;

function isRecentlyAuthenticated(request: Request): boolean {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) return false;

  const tokenParts = authorization.slice("Bearer ".length).split(".");
  if (tokenParts.length !== 3) return false;

  try {
    const encodedPayload = tokenParts[1]
      .replaceAll("-", "+")
      .replaceAll("_", "/")
      .padEnd(Math.ceil(tokenParts[1].length / 4) * 4, "=");
    const payload = JSON.parse(atob(encodedPayload)) as Record<string, unknown>;
    const authenticatedAt = payload.auth_time;
    if (
      typeof authenticatedAt !== "number" ||
      !Number.isSafeInteger(authenticatedAt)
    ) {
      return false;
    }

    const now = Math.floor(Date.now() / 1000);
    return authenticatedAt <= now + 60 &&
      now - authenticatedAt <= recentAuthenticationWindowSeconds;
  } catch {
    return false;
  }
}

async function removeUserPhotos(
  admin: AdminClient,
  userId: string,
  bucketName: string,
): Promise<void> {
  async function collectFiles(folder: string): Promise<void> {
    for (;;) {
      const { data, error } = await admin.storage.from(bucketName).list(
        folder,
        { limit: pageSize, offset: 0 },
      );
      if (error) throw error;
      if (data.length === 0) break;

      const directories: string[] = [];
      const paths: string[] = [];
      for (const entry of data) {
        const path = `${folder}/${entry.name}`;
        if (entry.id === null) {
          directories.push(path);
        } else {
          paths.push(path);
        }
      }

      for (const directory of directories) {
        await collectFiles(directory);
      }
      for (let index = 0; index < paths.length; index += pageSize) {
        const { error: removeError } = await admin.storage
          .from(bucketName)
          .remove(paths.slice(index, index + pageSize));
        if (removeError) throw removeError;
      }

      if (paths.length === 0 && directories.length === 0) {
        throw new Error("Storage cleanup could not make progress.");
      }
    }
  }

  await collectFiles(userId);
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: { code: "method_not_allowed" } }, 405);
  }

  const userId = await authenticatedUserId(request);
  if (userId instanceof Response) return userId;

  const rateLimitResponse = await enforceRateLimit(
    userId,
    "delete-account",
    3,
    3600,
  );
  if (rateLimitResponse) return rateLimitResponse;
  if (!isRecentlyAuthenticated(request)) {
    return jsonResponse(
      { error: { code: "reauthentication_required" } },
      403,
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("Supabase account deletion environment is not configured.");
    return jsonResponse({ error: { code: "function_not_configured" } }, 503);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    for (const bucketName of bucketNames) {
      await removeUserPhotos(admin, userId, bucketName);
    }
    const { error } = await admin.auth.admin.deleteUser(userId);
    if (error) {
      console.error("Account deletion failed:", error.code);
      return jsonResponse({ error: { code: "account_deletion_failed" } }, 502);
    }
    return jsonResponse({ deleted: true });
  } catch (error) {
    console.error(
      "Account deletion cleanup failed:",
      error instanceof Error ? error.name : "unknown error",
    );
    return jsonResponse(
      { error: { code: "account_deletion_cleanup_failed" } },
      502,
    );
  }
});
