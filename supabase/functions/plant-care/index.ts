import {
  authenticatedUserId,
  enforceRateLimit,
  requirePremiumEntitlement,
} from "../_shared/auth.ts";
import {
  corsHeaders,
  jsonResponse,
  readJsonBody,
} from "../_shared/http.ts";

type PlantCare = {
  description?: string;
  origin?: string;
  habitat?: string;
  plantType?: string;
  lifeCycle?: string;
  lifespan?: string;
  indoor?: string;
  outdoor?: string;
  dimension?: string;
  growthRate?: string;
  propagation?: string;
  watering?: string;
  wateringBenchmark?: string;
  sunlight?: string;
  soil?: string;
  soilPh?: string;
  hardinessZone?: string;
  minimumTemperature?: string;
  maximumTemperature?: string;
  idealTemperature?: string;
  humidity?: string;
  climate?: string;
  rainfallTolerance?: string;
  heatTolerance?: string;
  coldSensitivity?: string;
  fertilizer?: string;
  fertilizerFrequency?: string;
  nitrogen?: string;
  phosphorus?: string;
  potassium?: string;
  pruning?: string;
  floweringSeason?: string;
  droughtTolerance?: string;
  saltTolerance?: string;
  tropical?: string;
  maintenance?: string;
  pestSusceptibility?: string;
};

type CareResponse = {
  scientificName: string;
  source: "Perenual";
  sourceUrl: string;
  care: PlantCare;
};

const CARE_CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const MAX_CARE_CACHE_ENTRIES = 200;
const careCache = new Map<
  string,
  { value: CareResponse | null; expiresAt: number }
>();
const pendingCareRequests = new Map<string, Promise<CareResponse | null>>();

function normalizedName(value: string): string {
  return value.trim().replace(/\s+/g, " ").toLowerCase();
}

function text(value: unknown): string | undefined {
  if (typeof value === "string" && value.trim()) return value.trim();
  if (typeof value === "number" && Number.isFinite(value)) {
    return String(value);
  }
  if (Array.isArray(value)) {
    const values = value.filter(
      (item): item is string =>
        typeof item === "string" && item.trim().length > 0,
    );
    if (values.length > 0) return values.join(", ");
  }
  return undefined;
}

function booleanText(value: unknown): string | undefined {
  if (typeof value === "boolean") return value ? "Yes" : "No";
  if (value === 1 || value === 0) return value === 1 ? "Yes" : "No";
  if (typeof value === "string") {
    switch (value.trim().toLowerCase()) {
      case "true":
      case "yes":
      case "1":
        return "Yes";
      case "false":
      case "no":
      case "0":
        return "No";
    }
  }
  return text(value);
}

function benchmarkText(value: unknown): string | undefined {
  if (!value || typeof value !== "object") return undefined;
  const benchmark = value as Record<string, unknown>;
  const range = text(benchmark.value);
  const unit = text(benchmark.unit);
  return range ? `${range}${unit ? ` ${unit}` : ""}` : undefined;
}

function hardinessText(value: unknown): string | undefined {
  if (!value || typeof value !== "object") return undefined;
  const hardiness = value as Record<string, unknown>;
  const minimum = text(hardiness.min);
  const maximum = text(hardiness.max);
  if (minimum && maximum) return `${minimum}–${maximum}`;
  return minimum ?? maximum;
}

async function fetchCare(
  scientificName: string,
  apiKey: string,
): Promise<CareResponse | null> {
  const searchUrl = new URL("https://perenual.com/api/v2/species-list");
  searchUrl.searchParams.set("key", apiKey);
  searchUrl.searchParams.set("q", scientificName);
  searchUrl.searchParams.set("page", "1");

  const searchResponse = await fetch(searchUrl, {
    signal: AbortSignal.timeout(8_000),
  });
  if (!searchResponse.ok) {
    console.error("Perenual care search returned", searchResponse.status);
    throw new Error("perenual_search_failed");
  }

  const searchPayload = await searchResponse.json();
  const results = searchPayload &&
      typeof searchPayload === "object" &&
      Array.isArray(searchPayload.data)
    ? searchPayload.data as Record<string, unknown>[]
    : [];
  const match = results.find((item) => {
    const names = Array.isArray(item.scientific_name)
      ? item.scientific_name
      : [item.scientific_name];
    return names.some(
      (name) =>
        typeof name === "string" &&
        normalizedName(name) === normalizedName(scientificName),
    );
  });
  if (typeof match?.id !== "number" && typeof match?.id !== "string") {
    return null;
  }

  const detailsUrl = new URL(
    `https://perenual.com/api/v2/species/details/${encodeURIComponent(match.id)}`,
  );
  detailsUrl.searchParams.set("key", apiKey);
  const detailsResponse = await fetch(detailsUrl, {
    signal: AbortSignal.timeout(8_000),
  });
  if (!detailsResponse.ok) {
    console.error("Perenual care details returned", detailsResponse.status);
    throw new Error("perenual_details_failed");
  }

  const details = await detailsResponse.json();
  if (!details || typeof details !== "object") {
    throw new Error("perenual_invalid_response");
  }
  const providerData = details as Record<string, unknown>;
  const hardiness = hardinessText(providerData.hardiness);
  const care: PlantCare = {
    description: text(providerData.description),
    origin: text(providerData.origin),
    habitat: text(providerData.habitat),
    plantType: text(providerData.type),
    lifeCycle: text(providerData.cycle),
    lifespan: text(providerData.lifespan),
    indoor: booleanText(providerData.indoor),
    outdoor: booleanText(providerData.outdoor),
    dimension: text(providerData.dimension),
    growthRate: text(providerData.growth_rate),
    propagation: text(providerData.propagation),
    watering: text(providerData.watering),
    wateringBenchmark: benchmarkText(
      providerData.watering_general_benchmark,
    ),
    sunlight: text(providerData.sunlight),
    soil: text(providerData.soil),
    soilPh: text(providerData.soil_ph) ?? text(providerData.ph),
    hardinessZone: hardiness,
    minimumTemperature: text(providerData.minimum_temperature) ??
      text(providerData.min_temp),
    maximumTemperature: text(providerData.maximum_temperature) ??
      text(providerData.max_temp),
    idealTemperature: text(providerData.ideal_temperature),
    humidity: text(providerData.humidity),
    climate: text(providerData.climate),
    rainfallTolerance: text(providerData.rainfall_tolerance),
    heatTolerance: text(providerData.heat_tolerance),
    coldSensitivity: text(providerData.cold_sensitivity),
    fertilizer: text(providerData.fertilizer),
    fertilizerFrequency: text(providerData.fertilizer_frequency),
    nitrogen: text(providerData.nitrogen),
    phosphorus: text(providerData.phosphorus),
    potassium: text(providerData.potassium),
    pruning: text(providerData.pruning_month) ??
      text(providerData.pruning),
    floweringSeason: text(providerData.flowering_season),
    droughtTolerance: booleanText(providerData.drought_tolerant),
    saltTolerance: booleanText(providerData.salt_tolerant),
    tropical: booleanText(providerData.tropical),
    maintenance: text(providerData.maintenance),
    pestSusceptibility: text(providerData.pest_susceptibility),
  };
  if (!Object.values(care).some((value) => value != null)) {
    return null;
  }

  return {
    scientificName,
    source: "Perenual",
    sourceUrl: "https://perenual.com/",
    care,
  };
}

async function careFor(
  scientificName: string,
  apiKey: string,
): Promise<CareResponse | null> {
  const key = normalizedName(scientificName);
  const cached = careCache.get(key);
  if (cached && cached.expiresAt > Date.now()) return cached.value;
  if (cached) careCache.delete(key);

  const pending = pendingCareRequests.get(key);
  if (pending) return pending;

  const request = fetchCare(scientificName, apiKey);
  pendingCareRequests.set(key, request);
  try {
    const value = await request;
    if (careCache.size >= MAX_CARE_CACHE_ENTRIES) {
      const oldest = careCache.keys().next();
      if (!oldest.done) careCache.delete(oldest.value);
    }
    careCache.set(key, {
      value,
      expiresAt: Date.now() + CARE_CACHE_TTL_MS,
    });
    return value;
  } finally {
    pendingCareRequests.delete(key);
  }
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
    "plant-care",
    30,
    600,
  );
  if (rateLimitResponse) return rateLimitResponse;
  const entitlementResponse = await requirePremiumEntitlement(userId);
  if (entitlementResponse) return entitlementResponse;

  const parsed = await readJsonBody(request, 4096);
  if ("response" in parsed) return parsed.response;
  const scientificName = parsed.body.scientificName;
  if (
    typeof scientificName !== "string" ||
    scientificName.trim().length < 2 ||
    scientificName.trim().length > 120
  ) {
    return jsonResponse(
      { error: { code: "valid_scientific_name_required" } },
      400,
    );
  }

  const apiKey = Deno.env.get("PERENUAL_API_KEY");
  if (!apiKey) {
    return jsonResponse({ error: { code: "plant_care_not_configured" } }, 503);
  }

  try {
    const guide = await careFor(scientificName.trim(), apiKey);
    if (!guide) {
      return jsonResponse(
        { error: { code: "care_information_unavailable" } },
        404,
      );
    }
    return jsonResponse(guide);
  } catch (error) {
    console.error(
      "Plant care lookup failed:",
      error instanceof Error ? error.message : "unknown error",
    );
    return jsonResponse(
      { error: { code: "plant_care_provider_unavailable" } },
      502,
    );
  }
});
