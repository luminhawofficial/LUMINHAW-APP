
import {
  authenticate,
  enforceRequestLimit,
  preflight,
  requirePremium,
  reply,
} from "../_shared/common.ts";
import {providerJson, requiredSecret} from "../_shared/providers.ts";

Deno.serve(async (request: Request) => {
  const options = preflight(request);
  if (options) return options;
  if (request.method !== "POST") {
    return reply({error: "Method not allowed"}, 405);
  }

  const auth = await authenticate(request);
  if (auth instanceof Response) return auth;
  const limited = await enforceRequestLimit(auth.uid, "plant-id-health", 10);
  if (limited) return limited;
  const entitlement = await requirePremium(auth.uid);
  if (entitlement) return entitlement;

  const body = await request.json().catch(() => null);
  const images = body && typeof body === "object"
    ? (body as Record<string, unknown>).images
    : null;
  if (
    !Array.isArray(images) ||
    images.length < 1 ||
    images.length > 2 ||
    images.some((image: unknown) =>
      typeof image !== "string" ||
      image.length > 14_000_000 ||
      !/^data:image\/(jpeg|png);base64,(?=[A-Za-z0-9+/])(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(
        image,
      )
    )
  ) {
    return reply({error: "Supply 1–2 valid JPEG/PNG data URLs"}, 400);
  }

  let key: string;
  try {
    key = requiredSecret("PLANT_ID_API_KEY");
  } catch {
    return reply({error: "Plant.id is not configured"}, 503);
  }

  try {
    const data = await providerJson(
      "https://plant.id/api/v3/health_assessment",
      {
        method: "POST",
        headers: {"Content-Type": "application/json", "Api-Key": key},
        body: JSON.stringify({images, similar_images: false}),
      },
      30_000,
    );
    if (!data || typeof data !== "object" || !("result" in data)) {
      return reply({error: "Plant.id returned no assessment"}, 502);
    }
    return reply({
      source: "Plant.id",
      result: data.result,
      warning: "AI health results are suggestions, not a definitive diagnosis",
    });
  } catch (error) {
    console.error(
      "Plant.id health assessment failed:",
      error instanceof Error ? error.message : "unknown error",
    );
    return reply({error: "Plant.id assessment unavailable"}, 502);
  }
});
