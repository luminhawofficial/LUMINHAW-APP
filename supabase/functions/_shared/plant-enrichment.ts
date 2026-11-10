export const PLANT_DETAIL_FIELD_GUIDANCE = {
  tagalogName:
    "Commonly used Filipino/Tagalog name. If none is reliably known, give a clearly labeled descriptive translation, not a claimed traditional name.",
  bisayaName:
    "Commonly used Cebuano/Bisaya name. If none is reliably known, give a clearly labeled descriptive translation, not a claimed traditional name.",
  family: "Botanical family.",
  genus: "Botanical genus.",
  species: "Botanical species epithet or best-supported species identity.",
  description: "Short plain-language botanical description.",
  characteristics: "Identifying features, leaf form, and notable traits.",
  originHabitat: "Native geographic origin and natural habitat.",
  classification:
    "Plant type or classification, such as herb, shrub, tree, succulent, or vine.",
  suitability: "Whether it is generally suitable indoors, outdoors, or both.",
  lifespan:
    "Typical lifespan, distinguishing annual, perennial, or woody growth.",
  usesBenefits: "Common non-medical ornamental or practical uses.",
  dailyCare: "Simple routine care and maintenance.",
  weatherClimate: "Suitable general climate types, not today's local weather.",
  temperatureRange:
    "Ideal growing temperature and known minimum/maximum tolerance in Celsius; qualify uncertainty.",
  humidity: "Preferred humidity range, if known.",
  climateTypes: "Suitable broad climate types.",
  rainfallTolerance: "General tolerance of heavy or low rainfall and caveats.",
  heatTolerance: "General heat tolerance and signs of heat stress.",
  coldSensitivity: "Cold sensitivity and frost precautions.",
  seasonalCare: "Care adjustments for wet, dry, hot, or cool seasons.",
  soilCompatibility: "Recommended soil texture/type.",
  soilPH: "Preferred soil pH range, if known.",
  soilDrainage: "Drainage needs and how to avoid waterlogging.",
  soilMoisture: "Preferred soil moisture between watering.",
  soilMix: "Practical potting mix components and proportions only if reliable.",
  compost: "Suitable compost or organic matter, if appropriate.",
  wateringFrequency:
    "Typical interval range in days, explicitly conditional rather than a fixed rule.",
  wateringAmount: "How to water and when to stop.",
  wateringDrySeason: "How to adjust watering in dry or hot weather.",
  wateringRainySeason: "How to adjust watering during rainy or humid weather.",
  soilMoistureCheck: "Practical check for whether the soil needs water.",
  overwateringSigns: "Signs of overwatering.",
  underwateringSigns: "Signs of underwatering.",
  growthStageWatering: "How watering changes for seedlings and mature plants.",
  sunlightRequirements:
    "Full sun, partial sun, indirect light, or shade; qualify variation.",
  sunlightHours: "Approximate recommended daily light hours, if known.",
  lowLightSigns: "Signs of insufficient light.",
  excessiveLightSigns: "Signs of excessive sun or light.",
  fertilizer: "Suitable fertilizer type and N-P-K guidance, if known.",
  fertilizingFrequency:
    "Seasonal fertilizing interval and when to avoid feeding.",
  nutrientDeficiencies:
    "Common nutrient deficiency signs, with uncertainty noted.",
  fertilizerApplication: "Safe, practical fertilizer application instructions.",
  growthCharacteristics:
    "Growth rate and mature height/width, with units and uncertainty.",
  growthStages: "Typical growth stages.",
  propagation: "Common propagation methods and basic steps.",
  repotting: "When and how to repot, if normally grown in containers.",
  growingConditions: "Conditions that support healthy growth.",
} as const;

export const PLANT_ENRICHMENT_CACHE_VERSION = 6;

export const FREE_PLANT_ENRICHMENT_FIELDS = [
  "commonName",
  "scientificName",
  "family",
  "genus",
  "species",
  "tagalogName",
  "bisayaName",
  "description",
  "dailyCare",
  "careInstructions",
  "wateringFrequency",
  "wateringAmount",
  "sunlightRequirements",
] as const;

export function normalizePlantName(value: string): string {
  return value.trim().replace(/\s+/g, " ").toLowerCase();
}

export function boundedPlantText(
  value: unknown,
  maximum = 600,
): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed && trimmed.length <= maximum ? trimmed : undefined;
}

export function acceptedStringFields(
  value: Record<string, unknown>,
  allowedFields: readonly string[],
): Record<string, string> {
  const accepted: Record<string, string> = {};
  for (const field of allowedFields) {
    const text = boundedPlantText(value[field]);
    if (text) accepted[field] = text;
  }
  return accepted;
}

export function isCurrentPlantEnrichmentCache(value: unknown): boolean {
  return value !== null &&
    typeof value === "object" &&
    !Array.isArray(value) &&
    "schemaVersion" in value &&
    value.schemaVersion === PLANT_ENRICHMENT_CACHE_VERSION;
}

export function plantEnrichmentForPlan(
  value: unknown,
  isPremium: boolean,
): unknown {
  if (isPremium) return value;
  const response = value !== null && typeof value === "object" &&
      !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
  if (!response) return value;

  const allowedFields = new Set<string>(FREE_PLANT_ENRICHMENT_FIELDS);
  const profile = response.profile !== null &&
      typeof response.profile === "object" &&
      !Array.isArray(response.profile)
    ? response.profile as Record<string, unknown>
    : {};
  const aiGeneratedFields = new Set(
    Array.isArray(response.aiGeneratedFields)
      ? response.aiGeneratedFields.filter(
        (field): field is string => typeof field === "string",
      )
      : [],
  );
  const freeProfile = Object.fromEntries(
    Object.entries(profile).filter(([field, detail]) =>
      allowedFields.has(field) && !aiGeneratedFields.has(field) &&
      typeof detail === "string"
    ),
  );
  const visibleFields = new Set(Object.keys(freeProfile));
  const visibleMap = (value: unknown) => {
    if (value === null || typeof value !== "object" || Array.isArray(value)) {
      return {};
    }
    return Object.fromEntries(
      Object.entries(value).filter(([field]) => visibleFields.has(field)),
    );
  };

  return {
    ...response,
    profile: freeProfile,
    fieldSources: visibleMap(response.fieldSources),
    fieldStatuses: visibleMap(response.fieldStatuses),
    aiGeneratedFields: [],
    fieldGeneratedAt: {},
    generatedAt: null,
    unavailableFields: Array.isArray(response.unavailableFields)
      ? response.unavailableFields.filter(
        (field): field is string =>
          typeof field === "string" && allowedFields.has(field),
      )
      : [],
  };
}

export function plantFieldVerificationStatus(
  source: string | undefined,
  aiGenerated: boolean,
): "API Verified" | "AI-Generated" | "Needs Verification" | "Unavailable" {
  if (aiGenerated) return "AI-Generated";
  if (!source) return "Unavailable";
  if (
    /\b(gbif|perenual|trefle|kew|plants of the world online)\b/i.test(source)
  ) {
    return "API Verified";
  }
  return "Needs Verification";
}
