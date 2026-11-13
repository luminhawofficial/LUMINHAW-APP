import { authenticatedUserId, enforceRateLimit } from "../_shared/auth.ts";
import {
  corsHeaders,
  imageBase64From,
  jsonResponse,
  readJsonBody,
} from "../_shared/http.ts";
import { bestPlantIdentificationSuggestion } from "../_shared/plant-identification.ts";

type LocalizedNames = {
  tagalog: string | null;
  bisaya: string | null;
};

const localizedNameCache = new Map<
  string,
  { names: LocalizedNames; expiresAt: number }
>();

async function findLocalizedNames(
  scientificName: string,
): Promise<LocalizedNames> {
  const cacheKey = scientificName.toLowerCase().trim();
  const cached = localizedNameCache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now()) return cached.names;

  const unavailable: LocalizedNames = { tagalog: null, bisaya: null };
  try {
    const matchUrl = new URL("https://api.gbif.org/v1/species/match");
    matchUrl.searchParams.set("name", scientificName);
    matchUrl.searchParams.set("rank", "SPECIES");
    matchUrl.searchParams.set("kingdom", "Plantae");
    const matchResponse = await fetch(matchUrl, {
      signal: AbortSignal.timeout(5_000),
    });
    if (!matchResponse.ok) {
      console.error("GBIF name match returned", matchResponse.status);
      return unavailable;
    }

    const match = await matchResponse.json();
    if (
      typeof match.usageKey !== "number" ||
      match.rank !== "SPECIES" ||
      match.status !== "ACCEPTED" ||
      typeof match.confidence !== "number" ||
      match.confidence < 80
    ) {
      return unavailable;
    }

    const namesUrl = new URL(
      `https://api.gbif.org/v1/species/${match.usageKey}/vernacularNames`,
    );
    namesUrl.searchParams.set("limit", "1000");
    const namesResponse = await fetch(namesUrl, {
      signal: AbortSignal.timeout(5_000),
    });
    if (!namesResponse.ok) {
      console.error("GBIF vernacular names returned", namesResponse.status);
      return unavailable;
    }

    const payload = await namesResponse.json();
    if (!Array.isArray(payload.results)) return unavailable;
    const names: LocalizedNames = { ...unavailable };
    for (const item of payload.results) {
      if (!item || typeof item !== "object") continue;
      const record = item as Record<string, unknown>;
      if (
        typeof record.vernacularName !== "string" ||
        typeof record.language !== "string"
      ) {
        continue;
      }
      const language = record.language.toLowerCase().split(/[-_]/)[0];
      if (
        (language === "tgl" || language === "fil") &&
        names.tagalog === null
      ) {
        names.tagalog = record.vernacularName.trim() || null;
      }
      if (language === "ceb" && names.bisaya === null) {
        names.bisaya = record.vernacularName.trim() || null;
      }
    }

    if (localizedNameCache.size >= 500) {
      const oldestKey = localizedNameCache.keys().next().value;
      if (oldestKey !== undefined) localizedNameCache.delete(oldestKey);
    }
    localizedNameCache.set(cacheKey, {
      names,
      expiresAt: Date.now() +
        (names.tagalog || names.bisaya ? 86_400_000 : 600_000),
    });
    return names;
  } catch (error) {
    console.error(
      "GBIF localized plant-name lookup failed:",
      error instanceof Error ? error.name : "unknown error",
    );
    return unavailable;
  }
}

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
    "plant-identification",
    15,
    600,
  );
  if (rateLimitResponse) return rateLimitResponse;

  const parsed = await readJsonBody(request);
  if ("response" in parsed) return parsed.response;
  const imageBase64 = imageBase64From(parsed.body);
  if (!imageBase64) {
    return jsonResponse(
      { error: { code: "valid_image_required" } },
      400,
    );
  }

  const plantIdKey = Deno.env.get("PLANT_ID_API_KEY");
  const plantNetKey = Deno.env.get("PLANTNET_API_KEY");
  if (!plantIdKey && !plantNetKey) {
    return jsonResponse(
      { error: { code: "plant_identification_not_configured" } },
      503,
    );
  }

  let plantIdReturnedNoMatch = false;
  if (plantIdKey) {
    try {
      const upstream = await fetch(
        "https://plant.id/api/v3/identification",
        {
          method: "POST",
          headers: {
            "Api-Key": plantIdKey,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            images: [imageBase64],
            similar_images: true,
            details: ["common_names", "url", "description", "taxonomy"],
          }),
          signal: AbortSignal.timeout(30_000),
        },
      );
      if (upstream.ok) {
        const result = await upstream.json();
        const suggestions = result.result?.classification?.suggestions;
        if (Array.isArray(suggestions) && suggestions.length > 0) {
          const suggestion = bestPlantIdentificationSuggestion(suggestions);
          const details = suggestion?.details !== null &&
              typeof suggestion?.details === "object" &&
              !Array.isArray(suggestion.details)
            ? suggestion.details as Record<string, unknown>
            : undefined;
          const scientificName = (typeof details?.scientific_name === "string"
            ? details.scientific_name
            : undefined) ??
            (typeof suggestion?.name === "string"
              ? suggestion.name
              : undefined);
          const localizedNames = typeof scientificName === "string"
            ? await findLocalizedNames(scientificName)
            : { tagalog: null, bisaya: null };
          if (suggestion) {
            return jsonResponse({
              ...result,
              provider: "plant.id",
              localizedNames,
            });
          }
        }
        plantIdReturnedNoMatch = true;
        console.error("Plant.ID returned no identification suggestions.");
      }
      console.error("Plant.ID returned", upstream.status);
    } catch (error) {
      console.error(
        "Plant.ID request failed:",
        error instanceof Error ? error.name : "unknown error",
      );
    }
  }

  if (!plantNetKey) {
    return jsonResponse(
      {
        error: {
          code: plantIdReturnedNoMatch
            ? "plant_identification_no_match"
            : "plant_identification_provider_error",
        },
      },
      plantIdReturnedNoMatch ? 422 : 502,
    );
  }

  try {
    const bytes = Uint8Array.from(
      atob(imageBase64),
      (character) => character.charCodeAt(0),
    );
    const mimeType = bytes[0] === 0x89
      ? "image/png"
      : bytes[0] === 0x52
      ? "image/webp"
      : "image/jpeg";
    const form = new FormData();
    form.append("images", new Blob([bytes], { type: mimeType }), "plant-image");
    form.append("organs", "auto");

    const upstream = await fetch(
      `https://my-api.plantnet.org/v2/identify/all?api-key=${
        encodeURIComponent(plantNetKey)
      }`,
      {
        method: "POST",
        body: form,
        signal: AbortSignal.timeout(30_000),
      },
    );
    if (!upstream.ok) {
      console.error("PlantNet returned", upstream.status);
      return jsonResponse(
        {
          error: {
            code: upstream.status === 429
              ? "plant_identification_rate_limited"
              : "plant_identification_provider_error",
          },
        },
        upstream.status === 429 ? 429 : 502,
      );
    }

    const payload = await upstream.json();
    const first = payload.results?.[0];
    const species = first?.species;
    const scientificName = species?.scientificName;
    if (typeof scientificName !== "string" || scientificName.length === 0) {
      return jsonResponse(
        { error: { code: "plant_identification_no_match" } },
        422,
      );
    }
    const localizedNames = await findLocalizedNames(scientificName);
    return jsonResponse({
      provider: "plantnet",
      localizedNames,
      result: {
        classification: {
          suggestions: [{
            name: scientificName,
            probability: first.score,
            details: {
              scientific_name: scientificName,
              common_names: species.commonNames ?? [],
              taxonomy: { family: species.family?.scientificName },
            },
          }],
        },
      },
    });
  } catch (error) {
    console.error(
      "PlantNet request failed:",
      error instanceof Error ? error.name : "unknown error",
    );
    return jsonResponse(
      { error: { code: "plant_identification_unavailable" } },
      502,
    );
  }
}

Deno.serve(async (request: Request): Promise<Response> => {
  try {
    return await handleRequest(request);
  } catch (error) {
    console.error(
      "Plant identification handler failed:",
      error instanceof Error ? error.name : "unknown error",
    );
    return jsonResponse(
      { error: { code: "plant_identification_unavailable" } },
      500,
    );
  }
});
