import {
  authenticate,
  enforceRequestLimit,
  preflight,
  reply,
} from "../_shared/common.ts";
import {
  acceptedStringFields,
  boundedPlantText as text,
  isCurrentPlantEnrichmentCache,
  normalizePlantName as normalizedName,
  PLANT_DETAIL_FIELD_GUIDANCE,
  PLANT_ENRICHMENT_CACHE_VERSION,
  plantEnrichmentForPlan,
  plantFieldVerificationStatus,
} from "../_shared/plant-enrichment.ts";
import { requirePremiumEntitlement } from "../_shared/auth.ts";
import { boundedText, providerJson } from "../_shared/providers.ts";
import { findExactTreflePlant, searchTreflePlants } from "../_shared/trefle.ts";

type StringMap = Record<string, string>;

const CACHE_DAYS = 30;
const RETRY_MINUTES = 5;

function object(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

async function perenualProfile(
  scientificName: string,
): Promise<{ fields: StringMap; source: string } | null> {
  const key = Deno.env.get("PERENUAL_API_KEY");
  if (!key) return null;

  const search = new URL("https://perenual.com/api/v2/species-list");
  search.searchParams.set("key", key);
  search.searchParams.set("q", scientificName);
  search.searchParams.set("page", "1");
  const searchResponse = await fetch(search, {
    signal: AbortSignal.timeout(8_000),
  });
  if (!searchResponse.ok) {
    console.error("Perenual enrichment search returned", searchResponse.status);
    return null;
  }
  const searchPayload = await searchResponse.json();
  const entries = Array.isArray(searchPayload?.data)
    ? searchPayload.data as Record<string, unknown>[]
    : [];
  const match = entries.find((entry) => {
    const names = Array.isArray(entry.scientific_name)
      ? entry.scientific_name
      : [entry.scientific_name];
    return names.some((name) =>
      typeof name === "string" &&
      normalizedName(name) === normalizedName(scientificName)
    );
  });
  if (
    typeof match?.id !== "number" &&
    typeof match?.id !== "string"
  ) return null;

  const detailsUrl = new URL(
    `https://perenual.com/api/v2/species/details/${
      encodeURIComponent(match.id)
    }`,
  );
  detailsUrl.searchParams.set("key", key);
  const detailResponse = await fetch(detailsUrl, {
    signal: AbortSignal.timeout(8_000),
  });
  if (!detailResponse.ok) {
    console.error(
      "Perenual enrichment details returned",
      detailResponse.status,
    );
    return null;
  }
  const detail = object(await detailResponse.json());
  if (!detail) return null;
  const fields: StringMap = {};
  const mappings: Record<string, string[]> = {
    description: ["description"],
    characteristics: ["characteristics"],
    weatherClimate: ["climate"],
    soilCompatibility: ["soil"],
    wateringFrequency: ["watering_general_benchmark", "watering"],
    sunlightRequirements: ["sunlight"],
    temperatureRange: [
      "ideal_temperature",
      "minimum_temperature",
      "maximum_temperature",
    ],
    growthCharacteristics: ["growth_rate", "dimension", "propagation"],
    careInstructions: ["maintenance", "pruning"],
  };
  for (const [field, keys] of Object.entries(mappings)) {
    const values = keys
      .map((keyName) => {
        const value = detail[keyName];
        if (typeof value === "string" || typeof value === "number") {
          return String(value).trim();
        }
        if (Array.isArray(value)) {
          return value.filter((item) => typeof item === "string").join(", ")
            .trim();
        }
        if (value && typeof value === "object" && "value" in value) {
          const benchmark = value as Record<string, unknown>;
          return [benchmark.value, benchmark.unit]
            .filter((item) =>
              typeof item === "string" || typeof item === "number"
            )
            .join(" ")
            .trim();
        }
        return "";
      })
      .filter(Boolean);
    if (values.length) fields[field] = values.join("; ").slice(0, 600);
  }
  return Object.keys(fields).length ? { fields, source: "Perenual" } : null;
}

async function trefleProfile(
  scientificName: string,
): Promise<{ fields: StringMap; source: string } | null> {
  const token = Deno.env.get("TREFLE_API_KEY");
  if (!token) return null;

  const plants = await searchTreflePlants(scientificName, token);
  const match = findExactTreflePlant(plants, scientificName);
  if (!match) return null;

  const fields: StringMap = {};
  if (match.family) fields.family = match.family;
  if (match.genus) fields.genus = match.genus;
  return Object.keys(fields).length ? { fields, source: "Trefle" } : null;
}

async function gbifLocalNames(
  scientificName: string,
): Promise<{ fields: StringMap; source: string } | null> {
  try {
    const matchUrl = new URL("https://api.gbif.org/v1/species/match");
    matchUrl.searchParams.set("name", scientificName);
    matchUrl.searchParams.set("rank", "SPECIES");
    matchUrl.searchParams.set("kingdom", "Plantae");
    const matchResponse = await fetch(matchUrl, {
      signal: AbortSignal.timeout(5_000),
    });
    if (!matchResponse.ok) return null;
    const match = object(await matchResponse.json());
    if (
      typeof match?.usageKey !== "number" ||
      match.rank !== "SPECIES" ||
      match.status !== "ACCEPTED" ||
      typeof match.confidence !== "number" ||
      match.confidence < 80
    ) return null;

    const namesUrl = new URL(
      `https://api.gbif.org/v1/species/${match.usageKey}/vernacularNames`,
    );
    namesUrl.searchParams.set("limit", "1000");
    const namesResponse = await fetch(namesUrl, {
      signal: AbortSignal.timeout(5_000),
    });
    if (!namesResponse.ok) return null;
    const payload = object(await namesResponse.json());
    if (!Array.isArray(payload?.results)) return null;

    const fields: StringMap = {};
    for (const item of payload.results) {
      const record = object(item);
      const name = text(record?.vernacularName, 120);
      const language = text(record?.language, 20)?.toLowerCase().split(
        /[-_]/,
      )[0];
      if (!name || !language) continue;
      if ((language === "tgl" || language === "fil") && !fields.tagalogName) {
        fields.tagalogName = name;
      }
      if (language === "ceb" && !fields.bisayaName) {
        fields.bisayaName = name;
      }
    }
    return Object.keys(fields).length ? { fields, source: "GBIF" } : null;
  } catch (error) {
    console.error(
      "GBIF local-name lookup failed:",
      error instanceof Error ? error.message : "unknown error",
    );
    return null;
  }
}

async function geminiEnrichment(
  scientificName: string,
  known: StringMap,
  missing: string[],
): Promise<StringMap> {
  const key = Deno.env.get("GEMINI_API_KEY");
  if (!key || !missing.length) return {};
  const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
  const result = await providerJson(
    `https://generativelanguage.googleapis.com/v1beta/models/${
      encodeURIComponent(model)
    }:generateContent`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": key,
      },
      body: JSON.stringify({
        systemInstruction: {
          parts: [{
            text:
              "You are a careful botanical educator. Fill every requested missing field when a useful, species-appropriate answer is possible. Use the supplied scientific identity and known information; never contradict known facts. Clearly qualify estimates and variation. For Tagalog and Cebuano/Bisaya names, give an established local name only when known; otherwise provide a clearly labeled descriptive translation, never claim it is a traditional name. Return null only when no responsible answer is possible. Do not give medical, edible, or consumption advice. Do not claim suitability for current local weather.",
          }],
        },
        contents: [{
          role: "user",
          parts: [{
            text: JSON.stringify({
              task:
                "Return a JSON object with only the requested field names as keys and concise string or null values. Address every requested field. If a number or species-specific fact is uncertain, say so and provide a cautious general estimate only when useful. For Tagalog/Bisaya fallback names, prefix the value with 'Descriptive translation (not a verified traditional name): '.",
              scientificName,
              knownVerifiedInformation: known,
              requestedFields: missing.map((field) => ({
                field,
                guidance: PLANT_DETAIL_FIELD_GUIDANCE[
                  field as keyof typeof PLANT_DETAIL_FIELD_GUIDANCE
                ],
              })),
            }),
          }],
        }],
        generationConfig: {
          responseMimeType: "application/json",
          maxOutputTokens: 5000,
          temperature: 0.2,
        },
      }),
    },
    40_000,
  );
  const parts = result.candidates?.[0]?.content?.parts;
  const responseText = Array.isArray(parts)
    ? parts.map((part: Record<string, unknown>) =>
      typeof part.text === "string" ? part.text : ""
    ).join("").trim()
    : "";
  if (!responseText) throw new Error("gemini_empty_response");
  const parsed = object(JSON.parse(responseText));
  if (!parsed) throw new Error("gemini_invalid_response");
  return acceptedStringFields(parsed, missing);
}

async function handle(request: Request): Promise<Response> {
  const options = preflight(request);
  if (options) return options;
  if (request.method !== "POST") {
    return reply({ error: { code: "method_not_allowed" } }, 405);
  }
  const auth = await authenticate(request);
  if (auth instanceof Response) return auth;
  const limited = await enforceRequestLimit(auth.uid, "plant-enrich", 10);
  if (limited) return limited;
  const entitlementResponse = await requirePremiumEntitlement(auth.uid);
  let isPremium = true;
  if (entitlementResponse) {
    const payload = await entitlementResponse.clone().json().catch(() => null);
    if (
      entitlementResponse.status === 403 &&
      payload?.error?.code === "premium_entitlement_required"
    ) {
      isPremium = false;
    } else {
      return entitlementResponse;
    }
  }

  const body = object(await request.json().catch(() => null));
  const rawScientificName = body?.scientificName;
  const scientificName = boundedText(rawScientificName, 120);
  if (
    typeof rawScientificName !== "string" ||
    rawScientificName.trim().length < 2 ||
    rawScientificName.trim().length > 120
  ) {
    return reply({ error: { code: "valid_scientific_name_required" } }, 400);
  }
  const key = normalizedName(scientificName);
  const cacheKey = `${key}:${isPremium ? "premium" : "free"}`;
  const now = new Date();
  const cached = await auth.admin
    .from("plant_provider_cache")
    .select("response, expires_at")
    .eq("provider", "plant_enrichment")
    .eq("lookup_key", cacheKey)
    .maybeSingle();
  if (cached.error) {
    console.error("Plant enrichment cache read failed:", cached.error.code);
    return reply({ error: { code: "plant_enrichment_unavailable" } }, 503);
  }
  if (
    cached.data &&
    new Date(cached.data.expires_at).getTime() > now.getTime() &&
    isCurrentPlantEnrichmentCache(cached.data.response)
  ) {
    return reply(plantEnrichmentForPlan(cached.data.response, isPremium));
  }

  const profile: StringMap = {};
  const fieldSources: StringMap = {};
  const knownFields: StringMap = {};
  const inputSources = object(body?.fieldSources) ?? {};
  const sourceFor = (field: string) =>
    text(inputSources[field], 80) ?? text(body?.source, 80) ??
      "Plant catalog";
  for (
    const field of [
      "commonName",
      "scientificName",
      "family",
      "genus",
      "species",
      "kingdom",
      "phylum",
      "taxonomicClass",
      "order",
      "tagalogName",
      "bisayaName",
      "description",
    ]
  ) {
    const value = text(body?.[field], field.endsWith("Name") ? 120 : 600);
    if (!value) continue;
    profile[field] = value;
    fieldSources[field] = sourceFor(field);
    knownFields[field] = value;
  }

  let enrichmentError: string | undefined;
  let generated = new Set<string>();
  let unavailableFields: string[] = [];
  const generatedAt = now.toISOString();
  const [perenual, trefle, localNames] = await Promise.all([
    perenualProfile(scientificName).catch((error) => {
      console.error(
        "Perenual enrichment failed:",
        error instanceof Error ? error.name : "unknown error",
      );
      return null;
    }),
    trefleProfile(scientificName).catch((error) => {
      console.error(
        "Trefle enrichment failed:",
        error instanceof Error ? error.name : "unknown error",
      );
      return null;
    }),
    gbifLocalNames(scientificName),
  ]);
  for (const provider of [perenual, trefle]) {
    if (!provider) continue;
    for (const [field, value] of Object.entries(provider.fields)) {
      const currentStatus = plantFieldVerificationStatus(
        fieldSources[field],
        generated.has(field),
      );
      if (!profile[field] || currentStatus !== "API Verified") {
        profile[field] = value;
        fieldSources[field] = provider.source;
      }
      knownFields[field] = profile[field];
    }
  }
  if (localNames) {
    for (const [field, value] of Object.entries(localNames.fields)) {
      const currentStatus = plantFieldVerificationStatus(
        fieldSources[field],
        generated.has(field),
      );
      if (!profile[field] || currentStatus !== "API Verified") {
        profile[field] = value;
        fieldSources[field] = localNames.source;
      }
      knownFields[field] = profile[field];
    }
  }

  const missing = Object.keys(PLANT_DETAIL_FIELD_GUIDANCE).filter(
    (field) => !profile[field],
  );
  if (isPremium) {
    try {
      if (missing.length && !Deno.env.get("GEMINI_API_KEY")) {
        throw new Error("gemini_not_configured");
      }
      const aiFields = await geminiEnrichment(scientificName, knownFields, [
        ...missing,
      ]);
      for (const [field, value] of Object.entries(aiFields)) {
        profile[field] = value;
        fieldSources[field] = "LUMIN AI (Gemini)";
        generated.add(field);
      }
    } catch (error) {
      enrichmentError = error instanceof Error &&
          error.message === "gemini_not_configured"
        ? "AI enrichment is not configured."
        : "AI enrichment is temporarily unavailable.";
      unavailableFields = [...missing];
      console.error(
        "Gemini plant enrichment failed:",
        error instanceof Error ? error.message : "unknown error",
      );
    }
  }
  if (isPremium && !enrichmentError) {
    unavailableFields = missing.filter((field) => !profile[field]);
  }

  const fieldStatuses: Record<string, string> = {};
  const fieldGeneratedAt: Record<string, string> = {};
  const statusFields = new Set([
    ...Object.keys(PLANT_DETAIL_FIELD_GUIDANCE),
    ...Object.keys(profile),
  ]);
  for (const field of statusFields) {
    fieldStatuses[field] = profile[field]
      ? plantFieldVerificationStatus(fieldSources[field], generated.has(field))
      : "Unavailable";
    if (generated.has(field)) fieldGeneratedAt[field] = generatedAt;
  }

  const response = plantEnrichmentForPlan({
    success: true,
    schemaVersion: PLANT_ENRICHMENT_CACHE_VERSION,
    scientificName,
    profile,
    fieldSources,
    fieldStatuses,
    aiGeneratedFields: [...generated],
    fieldGeneratedAt,
    generatedAt: generated.size ? generatedAt : null,
    unavailableFields,
    enrichmentError,
  }, isPremium);
  const expiresAt = new Date(
    now.getTime() +
      (enrichmentError ? 0 : CACHE_DAYS * 86_400_000),
  ).toISOString();
  const { error: cacheError } = await auth.admin
    .from("plant_provider_cache")
    .upsert(
      {
        provider: "plant_enrichment",
        lookup_key: cacheKey,
        response,
        expires_at: expiresAt,
      },
      { onConflict: "provider,lookup_key" },
    );
  if (cacheError) {
    console.error("Plant enrichment cache write failed:", cacheError.code);
    return reply({ error: { code: "plant_enrichment_unavailable" } }, 503);
  }
  return reply(response);
}

Deno.serve(async (request: Request): Promise<Response> => {
  try {
    return await handle(request);
  } catch (error) {
    console.error(
      "Plant enrichment handler failed:",
      error instanceof Error ? error.message : "unknown error",
    );
    return reply({ error: { code: "plant_enrichment_unavailable" } }, 500);
  }
});
