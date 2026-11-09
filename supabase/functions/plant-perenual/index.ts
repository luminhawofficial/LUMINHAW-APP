
import {
  authenticate,
  enforceRequestLimit,
  preflight,
  reply,
} from "../_shared/common.ts";
import {providerJson, requiredSecret, boundedText} from "../_shared/providers.ts";

Deno.serve(async (request: Request) => {
  const options = preflight(request);
  if (options) return options;
  if (request.method !== "GET") {
    return reply({error: "Method not allowed"}, 405);
  }

  const auth = await authenticate(request);
  if (auth instanceof Response) return auth;
  const limited = await enforceRequestLimit(auth.uid, "plant-perenual", 60);
  if (limited) return limited;

  const query = boundedText(new URL(request.url).searchParams.get("q"), 100);
  if (query.length < 2) {
    return reply({error: "q must be 2–100 characters"}, 400);
  }

  let key: string;
  try {
    key = requiredSecret("PERENUAL_API_KEY");
  } catch {
    return reply({error: "Perenual is not configured"}, 503);
  }

  try {
    const data = await providerJson(
      `https://perenual.com/api/v2/species-list?key=${encodeURIComponent(key)}&q=${encodeURIComponent(query)}&page=1`,
    );
    const records = Array.isArray(data?.data) ? data.data : [];
    const plants = records.slice(0, 20).flatMap((plant: Record<string, unknown>) => {
      const scientificName = Array.isArray(plant.scientific_name)
        ? plant.scientific_name.find((name: unknown) =>
          typeof name === "string" && name.trim()
        )
        : null;
      if (typeof scientificName !== "string") return [];
      const image = plant.default_image &&
          typeof plant.default_image === "object"
        ? plant.default_image as Record<string, unknown>
        : {};
      return [{
        provider_id: plant.id ?? null,
        common_name: typeof plant.common_name === "string"
          ? plant.common_name
          : null,
        scientific_name: scientificName,
        image_url: image.regular_url ?? image.original_url ?? null,
        watering: plant.watering ?? null,
        sunlight: plant.sunlight ?? null,
        image_attribution:
          "Verify provider image rights and attribution before reuse",
      }];
    });
    return reply({source: "Perenual", plants});
  } catch (error) {
    console.error(
      "Perenual search failed:",
      error instanceof Error ? error.name : "unknown error",
    );
    return reply({error: "Perenual request unavailable"}, 502);
  }
});
