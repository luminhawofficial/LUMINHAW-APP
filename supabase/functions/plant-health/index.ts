import {
  authenticatedUserId,
  enforceRateLimit,
  requirePremiumEntitlement,
} from "../_shared/auth.ts";
import {
  corsHeaders,
  imageDataUriFrom,
  jsonResponse,
  readJsonBody,
} from "../_shared/http.ts";

async function handleRequest(request: Request): Promise<Response> {
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
    "plant-health",
    10,
    600,
  );
  if (rateLimitResponse) return rateLimitResponse;
  const entitlementResponse = await requirePremiumEntitlement(userId);
  if (entitlementResponse) return entitlementResponse;

  const parsed = await readJsonBody(request);
  if ("response" in parsed) return parsed.response;
  const imageDataUri = imageDataUriFrom(parsed.body);
  if (!imageDataUri) {
    return jsonResponse(
      { error: { code: "valid_image_required" } },
      400,
    );
  }

  const apiKey = Deno.env.get("PLANT_ID_API_KEY");
  if (!apiKey) {
    return jsonResponse(
      { error: { code: "plant_health_not_configured" } },
      503,
    );
  }

  try {
    const upstream = await fetch(
      "https://plant.id/api/v3/health_assessment",
      {
        method: "POST",
        headers: {
          "Api-Key": apiKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          images: [imageDataUri],
          details: ["local_name", "description", "treatment", "cause"],
        }),
        signal: AbortSignal.timeout(30_000),
      },
    );
    if (!upstream.ok) {
      console.error("Plant health provider returned", upstream.status);
      return jsonResponse(
        {
          error: {
            code: upstream.status === 429
              ? "plant_health_rate_limited"
              : "plant_health_provider_error",
          },
        },
        upstream.status === 429 ? 429 : 502,
      );
    }

    return jsonResponse(await upstream.json());
  } catch (error) {
    console.error(
      "Plant health request failed:",
      error instanceof Error ? error.name : "unknown error",
    );
    return jsonResponse(
      { error: { code: "plant_health_unavailable" } },
      502,
    );
  }
}

Deno.serve(async (request: Request): Promise<Response> => {
  try {
    return await handleRequest(request);
  } catch (error) {
    console.error(
      "Plant health handler failed:",
      error instanceof Error ? error.name : "unknown error",
    );
    return jsonResponse(
      { error: { code: "plant_health_unavailable" } },
      500,
    );
  }
});
