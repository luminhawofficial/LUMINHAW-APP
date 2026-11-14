const plantFactFields = [
  "image_url",
  "common_name",
  "scientific_name",
  "tagalog_name",
  "bisaya_name",
  "description",
  "water_requirement",
  "sunlight_requirement",
  "soil_requirement",
  "fertilizer",
  "growth_tips",
  "common_diseases",
  "treatment",
  "toxicity",
] as const;

type PlantFactField = typeof plantFactFields[number];

const fieldLimits: Record<PlantFactField, number> = {
  image_url: 2048,
  common_name: 160,
  scientific_name: 200,
  tagalog_name: 160,
  bisaya_name: 160,
  description: 12000,
  water_requirement: 4000,
  sunlight_requirement: 4000,
  soil_requirement: 4000,
  fertilizer: 4000,
  growth_tips: 4000,
  common_diseases: 4000,
  treatment: 4000,
  toxicity: 32,
};

const toxicityValues = new Set([
  "unknown",
  "safe",
  "toxic_pets",
  "toxic_humans",
  "toxic_pets_humans",
]);

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type AdminPlantCatalogInput = {
  id: string | null;
  catalog: {
    common_name: string;
    scientific_name: string;
    tagalog_name: string | null;
    bisaya_name: string | null;
    description: string | null;
  };
  care: {
    water_requirements: string | null;
    sunlight_requirements: string | null;
    soil_requirements: string | null;
    fertilizer: string | null;
    growth_tips: string | null;
    common_diseases: string | null;
    treatment: string | null;
    toxicity: string;
  };
  imageUrl: string | null;
  imageSourceUrl: string | null;
  fieldReferences: Record<string, string[]>;
  dateUpdated: string;
};

export type AdminPlantCatalogParseResult =
  | { ok: true; value: AdminPlantCatalogInput }
  | {
    ok: false;
    code: "invalid_plant_catalog_record" | "plant_reference_required";
  };

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isHttpsUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && url.hostname !== "" &&
      url.username === "" && url.password === "";
  } catch {
    return false;
  }
}

function isValidDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(parsed.getTime()) &&
    parsed.toISOString().slice(0, 10) === value;
}

export function parseAdminPlantCatalogInput(
  body: Record<string, unknown>,
  isUpdate: boolean,
): AdminPlantCatalogParseResult {
  let id: string | null = null;
  if (isUpdate) {
    if (typeof body.id !== "string" || !uuidPattern.test(body.id)) {
      return { ok: false, code: "invalid_plant_catalog_record" };
    }
    id = body.id;
  } else if (body.id !== undefined && body.id !== null && body.id !== "") {
    return { ok: false, code: "invalid_plant_catalog_record" };
  }

  const values = {} as Record<PlantFactField, string>;
  for (const field of plantFactFields) {
    const raw = body[field];
    if (raw === undefined || raw === null) {
      values[field] = field === "toxicity" ? "unknown" : "";
      continue;
    }
    if (typeof raw !== "string") {
      return { ok: false, code: "invalid_plant_catalog_record" };
    }
    const value = raw.trim();
    if (value.length > fieldLimits[field]) {
      return { ok: false, code: "invalid_plant_catalog_record" };
    }
    values[field] = value;
  }

  if (
    values.common_name === "" ||
    values.scientific_name === "" ||
    !toxicityValues.has(values.toxicity) ||
    (values.image_url !== "" && !isHttpsUrl(values.image_url))
  ) {
    return { ok: false, code: "invalid_plant_catalog_record" };
  }

  const dateUpdated = body.date_updated;
  if (typeof dateUpdated !== "string" || !isValidDate(dateUpdated)) {
    return { ok: false, code: "invalid_plant_catalog_record" };
  }

  const rawReferences = body.field_references;
  if (!isRecord(rawReferences)) {
    return { ok: false, code: "plant_reference_required" };
  }
  const knownFields = new Set<string>(plantFactFields);
  if (Object.keys(rawReferences).some((field) => !knownFields.has(field))) {
    return { ok: false, code: "invalid_plant_catalog_record" };
  }

  const fieldReferences: Record<string, string[]> = {};
  for (const field of plantFactFields) {
    const populated = field === "toxicity"
      ? values[field] !== "unknown"
      : values[field] !== "";
    if (!populated) continue;

    const rawSources = rawReferences[field];
    if (!Array.isArray(rawSources) || rawSources.length === 0) {
      return { ok: false, code: "plant_reference_required" };
    }
    const sources: string[] = [];
    let totalLength = 0;
    for (const rawSource of rawSources) {
      if (typeof rawSource !== "string" || rawSource.trim() === "") {
        return { ok: false, code: "plant_reference_required" };
      }
      const source = rawSource.trim();
      totalLength += source.length + 1;
      if (totalLength > 4000) {
        return { ok: false, code: "invalid_plant_catalog_record" };
      }
      sources.push(source);
    }
    fieldReferences[field] = sources;
  }

  const imageSourceUrl = (fieldReferences.image_url ?? []).find(isHttpsUrl) ??
    null;

  return {
    ok: true,
    value: {
      id,
      catalog: {
        common_name: values.common_name,
        scientific_name: values.scientific_name,
        tagalog_name: values.tagalog_name || null,
        bisaya_name: values.bisaya_name || null,
        description: values.description || null,
      },
      care: {
        water_requirements: values.water_requirement || null,
        sunlight_requirements: values.sunlight_requirement || null,
        soil_requirements: values.soil_requirement || null,
        fertilizer: values.fertilizer || null,
        growth_tips: values.growth_tips || null,
        common_diseases: values.common_diseases || null,
        treatment: values.treatment || null,
        toxicity: values.toxicity,
      },
      imageUrl: values.image_url || null,
      imageSourceUrl,
      fieldReferences,
      dateUpdated,
    },
  };
}
