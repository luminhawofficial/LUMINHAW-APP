import {
  acceptedStringFields,
  boundedPlantText,
  FREE_PLANT_ENRICHMENT_FIELDS,
  isCurrentPlantEnrichmentCache,
  normalizePlantName,
  PLANT_DETAIL_FIELD_GUIDANCE,
  PLANT_ENRICHMENT_CACHE_VERSION,
  plantEnrichmentForPlan,
  plantFieldVerificationStatus,
} from "./plant-enrichment.ts";

Deno.test("plant names normalize whitespace and case for cache keys", () => {
  if (normalizePlantName("  Monstera   Deliciosa ") !== "monstera deliciosa") {
    throw new Error("plant name was not normalized");
  }
});

Deno.test("plant profile text accepts only nonempty bounded strings", () => {
  if (boundedPlantText("  Partial shade  ", 20) !== "Partial shade") {
    throw new Error("plant text was not trimmed");
  }
  if (
    boundedPlantText("too long", 3) !== undefined ||
    boundedPlantText(24) !== undefined ||
    boundedPlantText("   ") !== undefined
  ) {
    throw new Error("invalid plant text was accepted");
  }
});

Deno.test("AI enrichment keeps only requested, bounded string fields", () => {
  const accepted = acceptedStringFields({
    description: "  Verified description  ",
    wateringFrequency: "Every 4-7 days",
    unrequestedField: "Must not be exposed",
    soilCompatibility: { guess: "clay" },
  }, ["description", "soilCompatibility"]);

  if (
    accepted.description !== "Verified description" ||
    Object.keys(accepted).length !== 1
  ) {
    throw new Error("unrequested or non-string AI fields were accepted");
  }
});

Deno.test("Gemini fallback covers missing names and plant-care sections", () => {
  const requestedFields = Object.keys(PLANT_DETAIL_FIELD_GUIDANCE);
  for (
    const field of [
      "tagalogName",
      "bisayaName",
      "originHabitat",
      "soilPH",
      "wateringRainySeason",
      "nutrientDeficiencies",
      "propagation",
    ]
  ) {
    if (!requestedFields.includes(field)) {
      throw new Error(`missing Gemini fallback field: ${field}`);
    }
  }
});

Deno.test("old cached plant profiles are refreshed after field schema changes", () => {
  if (
    isCurrentPlantEnrichmentCache({ schemaVersion: 1 }) ||
    isCurrentPlantEnrichmentCache(null) ||
    !isCurrentPlantEnrichmentCache({
      schemaVersion: PLANT_ENRICHMENT_CACHE_VERSION,
    })
  ) {
    throw new Error("plant enrichment cache version was not enforced");
  }
});

Deno.test("free plant enrichment exposes basic facts but withholds premium data", () => {
  const response = {
    profile: {
      commonName: "Papaya",
      scientificName: "Carica papaya",
      family: "Caricaceae",
      genus: "Carica",
      species: "papaya",
      description: "A tropical fruiting plant.",
      dailyCare: "Water when the soil begins to dry.",
      nutrientDeficiencies: "Yellowing can have several causes.",
      originHabitat: "Native to Central America.",
      advancedAiFact: "Do not expose.",
      aiOnlyCare: "Do not expose.",
    },
    fieldSources: {
      commonName: "Plant.ID",
      nutrientDeficiencies: "LUMIN AI (Gemini)",
      originHabitat: "Perenual",
    },
    fieldStatuses: {
      commonName: "Needs Verification",
      nutrientDeficiencies: "AI-Generated",
      originHabitat: "API Verified",
    },
    aiGeneratedFields: ["nutrientDeficiencies", "aiOnlyCare"],
    fieldGeneratedAt: { nutrientDeficiencies: "2026-11-10T00:00:00.000Z" },
    generatedAt: "2026-11-10T00:00:00.000Z",
    unavailableFields: ["description", "soilPH", "originHabitat"],
  };
  const free = plantEnrichmentForPlan(response, false) as typeof response;
  const premium = plantEnrichmentForPlan(response, true) as typeof response;
  const freeFieldNames = Object.keys(free.profile);

  if (
    free.profile.commonName !== "Papaya" ||
    free.profile.family !== "Caricaceae" ||
    free.profile.dailyCare !== "Water when the soil begins to dry." ||
    freeFieldNames.includes("nutrientDeficiencies") ||
    freeFieldNames.includes("originHabitat") ||
    freeFieldNames.includes("advancedAiFact") ||
    free.fieldSources.nutrientDeficiencies !== undefined ||
    free.fieldStatuses.nutrientDeficiencies !== undefined ||
    free.aiGeneratedFields.length !== 0 ||
    free.generatedAt !== null ||
    free.unavailableFields.includes("soilPH") ||
    premium.profile.nutrientDeficiencies !==
      "Yellowing can have several causes." ||
    !FREE_PLANT_ENRICHMENT_FIELDS.includes("dailyCare")
  ) {
    throw new Error("plan-based plant enrichment was not filtered correctly");
  }
});

Deno.test("plant field statuses distinguish verified, generated, and missing", () => {
  const statuses = [
    plantFieldVerificationStatus("GBIF", false),
    plantFieldVerificationStatus("Perenual", false),
    plantFieldVerificationStatus("Trefle", false),
    plantFieldVerificationStatus("Plant.ID", false),
    plantFieldVerificationStatus("LUMIN AI (Gemini)", true),
    plantFieldVerificationStatus(undefined, false),
  ];
  if (
    statuses.join("|") !==
      "API Verified|API Verified|API Verified|Needs Verification|AI-Generated|Unavailable"
  ) {
    throw new Error("plant field verification status was misclassified");
  }
});
