import { authenticatedUserId, enforceRateLimit } from "../_shared/auth.ts";
import { corsHeaders, jsonResponse, readJsonBody } from "../_shared/http.ts";

type CatalogPlant = {
  commonName: string;
  scientificName: string;
  family: string;
  kingdom?: string;
  phylum?: string;
  taxonomicClass?: string;
  genus?: string;
  species?: string;
  rank?: string;
  taxonomicStatus?: string;
  order?: string;
  description?: string;
  tagalogName?: string;
  bisayaName?: string;
  formerScientificName?: string;
  acceptedTaxonId?: string;
  imageUrl: string | null;
  imageAttribution?: string;
  imageLicense?: string;
  imageLicenseUrl?: string;
  imageReferenceUrl?: string;
  source: "perenual" | "gbif";
};

type CatalogImage = {
  imageUrl: string;
  imageAttribution?: string;
  imageLicense: string;
  imageLicenseUrl: string;
  imageReferenceUrl: string;
};

type LocalizedNames = {
  tagalogName?: string;
  bisayaName?: string;
};

const IMAGE_CACHE_TTL_MS = 6 * 60 * 60 * 1000;
const EMPTY_IMAGE_CACHE_TTL_MS = 2 * 60 * 1000;
const MAX_IMAGE_CACHE_ENTRIES = 500;
const imageCache = new Map<
  string,
  { image: CatalogImage | null; expiresAt: number }
>();
const pendingImageLookups = new Map<string, Promise<CatalogImage | null>>();
const localizedNameCache = new Map<
  string,
  { names: LocalizedNames; expiresAt: number }
>();

function firstString(value: unknown): string | null {
  if (typeof value === "string" && value.trim()) return value.trim();
  if (Array.isArray(value)) {
    for (const item of value) {
      if (typeof item === "string" && item.trim()) return item.trim();
    }
  }
  return null;
}

function reusableLicense(value: unknown): {
  name: string;
  url: string;
} | null {
  const license = firstString(value);
  if (!license) return null;

  const normalized = license
    .toLowerCase()
    .replaceAll("_", "-")
    .replace(/\s+/g, "-");
  if (
    normalized.includes("creativecommons.org/publicdomain/zero/1.0") ||
    /^cc0(?:-1\.0)?$/.test(normalized)
  ) {
    return {
      name: "CC0 1.0",
      url: "https://creativecommons.org/publicdomain/zero/1.0/",
    };
  }

  const byUrl = normalized.match(
    /creativecommons\.org\/licenses\/by\/([234])\.0(?:\/|$)/,
  );
  const byLabel = normalized.match(/^cc-?by-?([234])(?:[.-]0)?$/);
  const version = byUrl?.[1] ?? byLabel?.[1];
  if (!version) return null;

  return {
    name: `CC BY ${version}.0`,
    url: `https://creativecommons.org/licenses/by/${version}.0/`,
  };
}

function httpsUrl(value: unknown): string | null {
  const candidate = firstString(value);
  if (!candidate) return null;
  try {
    const url = new URL(candidate);
    return url.protocol === "https:" ? url.toString() : null;
  } catch {
    return null;
  }
}

async function fetchImageForTaxon(
  taxonKey: string,
): Promise<CatalogImage | null> {
  try {
    const url = new URL("https://api.gbif.org/v1/occurrence/search");
    url.searchParams.set("taxon_key", taxonKey);
    url.searchParams.set("media_type", "StillImage");
    for (const license of ["CC0_1_0", "CC_BY_4_0"]) {
      url.searchParams.append("license", license);
    }
    url.searchParams.set("limit", "10");

    const response = await fetch(url, {
      signal: AbortSignal.timeout(8_000),
    });
    if (!response.ok) {
      console.error("GBIF image search returned", response.status);
      return null;
    }

    const payload = await response.json();
    if (!Array.isArray(payload.results)) return null;

    for (const occurrence of payload.results) {
      if (!occurrence || typeof occurrence !== "object") continue;
      const key = (occurrence as Record<string, unknown>).key;
      const occurrenceKey = typeof key === "number" ? String(key) : null;
      const occurrencePage = occurrenceKey
        ? `https://www.gbif.org/occurrence/${occurrenceKey}`
        : null;
      const mediaList = (occurrence as Record<string, unknown>).media;
      if (!Array.isArray(mediaList)) continue;

      for (const media of mediaList) {
        if (!media || typeof media !== "object") continue;
        const record = media as Record<string, unknown>;
        if (
          typeof record.type === "string" &&
          record.type.toLowerCase() !== "stillimage"
        ) {
          continue;
        }
        const imageUrl = httpsUrl(record.identifier);
        const license = reusableLicense(record.license);
        if (!imageUrl || !license) continue;

        const imageAttribution = firstString(record.creator) ??
          firstString(record.rightsHolder) ??
          firstString(record.publisher) ??
          undefined;
        if (license.name !== "CC0 1.0" && !imageAttribution) continue;

        return {
          imageUrl,
          imageAttribution,
          imageLicense: license.name,
          imageLicenseUrl: license.url,
          imageReferenceUrl: httpsUrl(record.references) ?? occurrencePage ??
            imageUrl,
        };
      }
    }
  } catch (error) {
    console.error(
      "GBIF image search failed:",
      error instanceof Error ? error.name : "unknown error",
    );
  }

  return null;
}

async function fetchLocalizedNamesByKey(
  taxonKey: string,
): Promise<LocalizedNames> {
  const cached = localizedNameCache.get(taxonKey);
  if (cached && cached.expiresAt > Date.now()) return cached.names;
  const names: LocalizedNames = {};
  try {
    const url = new URL(
      `https://api.gbif.org/v1/species/${encodeURIComponent(taxonKey)}/vernacularNames`,
    );
    url.searchParams.set("limit", "1000");
    const response = await fetch(url, { signal: AbortSignal.timeout(5_000) });
    if (!response.ok) return names;
    const payload = await response.json();
    if (Array.isArray(payload.results)) {
      for (const item of payload.results) {
        if (
          !item ||
          typeof item.vernacularName !== "string" ||
          typeof item.language !== "string"
        ) continue;
        const language = item.language.toLowerCase().split(/[-_]/)[0];
        const name = item.vernacularName.trim();
        if (!name) continue;
        if (
          (language === "tgl" || language === "fil") &&
          !names.tagalogName
        ) names.tagalogName = name;
        if (language === "ceb" && !names.bisayaName) {
          names.bisayaName = name;
        }
      }
    }
  } catch (error) {
    console.error(
      "GBIF localized names failed:",
      error instanceof Error ? error.name : "unknown error",
    );
  }
  if (localizedNameCache.size >= 500) {
    const oldest = localizedNameCache.keys().next().value;
    if (oldest !== undefined) localizedNameCache.delete(oldest);
  }
  localizedNameCache.set(taxonKey, {
    names,
    expiresAt: Date.now() + (Object.keys(names).length ? 86_400_000 : 600_000),
  });
  return names;
}

async function fetchLocalizedNamesByScientificName(
  scientificName: string,
): Promise<LocalizedNames> {
  try {
    const url = new URL("https://api.gbif.org/v1/species/match");
    url.searchParams.set("name", scientificName);
    url.searchParams.set("rank", "SPECIES");
    url.searchParams.set("kingdom", "Plantae");
    const response = await fetch(url, { signal: AbortSignal.timeout(5_000) });
    if (!response.ok) return {};
    const match = await response.json();
    if (
      typeof match.usageKey !== "number" ||
      match.status !== "ACCEPTED" ||
      match.rank !== "SPECIES" ||
      typeof match.confidence !== "number" ||
      match.confidence < 80
    ) return {};
    return await fetchLocalizedNamesByKey(String(match.usageKey));
  } catch (error) {
    console.error(
      "GBIF local-name match failed:",
      error instanceof Error ? error.name : "unknown error",
    );
    return {};
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
    "plant-catalog",
    60,
    600,
  );
  if (rateLimitResponse) return rateLimitResponse;

  const parsed = await readJsonBody(request, 4096);
  if ("response" in parsed) return parsed.response;
  const query = parsed.body.q ?? parsed.body.query;
  if (
    typeof query !== "string" ||
    query.trim().length < 2 ||
    query.trim().length > 80
  ) {
    return jsonResponse(
      { error: { code: "query_must_be_between_2_and_80_characters" } },
      400,
    );
  }

  const term = query.trim();
  const perenualKey = Deno.env.get("PERENUAL_API_KEY");
  if (perenualKey) {
    try {
      const url = new URL("https://perenual.com/api/species-list");
      url.searchParams.set("key", perenualKey);
      url.searchParams.set("q", term);
      const response = await fetch(url, {
        signal: AbortSignal.timeout(12_000),
      });
      if (response.ok) {
        const payload = await response.json();
        const plants = (payload.data ?? [])
          .filter((item: Record<string, unknown>) =>
            Array.isArray(item.scientific_name) &&
            typeof item.scientific_name[0] === "string"
          )
          .slice(0, 20)
          .map((item: Record<string, unknown>) => {
            const scientificName = Array.isArray(item.scientific_name)
              ? item.scientific_name.find(
                (name): name is string => typeof name === "string",
              )
              : undefined;
            if (!scientificName) return null;
            const image = item.default_image as
              | Record<string, unknown>
              | undefined;
            return {
              commonName: firstString(item.common_name) ??
                scientificName,
              scientificName,
              family: firstString(item.family) ?? "Not listed",
              genus: firstString(item.genus) ?? undefined,
              species: firstString(item.species) ?? undefined,
              taxonomicStatus: firstString(item.taxonomicStatus) ?? undefined,
              imageUrl: httpsUrl(image?.thumbnail) ??
                httpsUrl(image?.small_url) ??
                httpsUrl(image?.regular_url) ??
                httpsUrl(image?.original_url),
              imageAttribution: firstString(image?.creator) ??
                firstString(image?.author) ??
                firstString(image?.rightsHolder) ??
                undefined,
              imageLicense: firstString(image?.license_name) ??
                firstString(image?.license) ??
                undefined,
              imageLicenseUrl: firstString(image?.license_url) ?? undefined,
              imageReferenceUrl: firstString(image?.original_url) ?? undefined,
              source: "perenual" as const,
            };
          })
          .filter(
            (plant: CatalogPlant | null): plant is CatalogPlant =>
              plant !== null,
          );
        if (plants.length > 0) {
          let nextIndex = 0;
          await Promise.all(
            Array.from({ length: Math.min(3, plants.length) }, async () => {
              while (nextIndex < plants.length) {
                const index = nextIndex++;
                const names = await fetchLocalizedNamesByScientificName(
                  plants[index].scientificName,
                );
                Object.assign(plants[index], names);
              }
            }),
          );
          return jsonResponse({
            success: true,
            source: "Perenual",
            results: plants,
          });
        }
      } else {
        console.error("Perenual returned", response.status);
      }
    } catch (error) {
      console.error(
        "Perenual search failed:",
        error instanceof Error ? error.name : "unknown error",
      );
    }
  }

  try {
    const url = new URL("https://api.gbif.org/v1/species/search");
    url.searchParams.set("q", term);
    url.searchParams.set("rank", "SPECIES");
    url.searchParams.set("status", "ACCEPTED");
    url.searchParams.set("limit", "20");
    const response = await fetch(url, {
      signal: AbortSignal.timeout(12_000),
    });
    if (!response.ok) {
      console.error("GBIF returned", response.status);
      return jsonResponse(
        { error: { code: "plant_catalog_provider_error" } },
        502,
      );
    }

    const payload = await response.json();
    const plants: CatalogPlant[] = (payload.results ?? [])
      .filter((item: Record<string, unknown>) =>
        typeof item.scientificName === "string" &&
        typeof item.key === "number" &&
        (typeof item.rank !== "string" ||
          item.rank.toUpperCase() === "SPECIES") &&
        (typeof item.taxonomicStatus !== "string" ||
          item.taxonomicStatus.toUpperCase() === "ACCEPTED")
      )
      .slice(0, 20)
      .map((item: Record<string, unknown>) => {
        const descriptions = item.descriptions;
        const description = typeof descriptions === "string"
          ? descriptions
          : Array.isArray(descriptions)
          ? firstString(
            descriptions.map((entry: unknown) =>
              entry !== null && typeof entry === "object"
                ? (entry as Record<string, unknown>).description ??
                  (entry as Record<string, unknown>).text
                : null
            ),
          )
          : null;
        const key = item.nubKey ?? item.acceptedKey ?? item.speciesKey ??
          item.key;
        return {
          commonName: firstString(item.vernacularName) ??
            firstString(item.canonicalName) ??
            String(item.scientificName),
          scientificName: firstString(item.acceptedScientificName) ??
            firstString(item.acceptedName) ??
            String(item.scientificName),
          family: firstString(item.family) ?? "Not listed",
          kingdom: firstString(item.kingdom) ?? undefined,
          phylum: firstString(item.phylum) ?? undefined,
          taxonomicClass: firstString(item.class) ?? undefined,
          genus: firstString(item.genus) ?? undefined,
          species: firstString(item.species) ?? undefined,
          rank: firstString(item.rank) ?? undefined,
          taxonomicStatus: firstString(item.taxonomicStatus) ?? undefined,
          order: firstString(item.order) ?? undefined,
          description: description ?? undefined,
          formerScientificName: firstString(item.formerScientificName) ??
            firstString(item.synonym) ??
            undefined,
          acceptedTaxonId: key == null ? undefined : String(key),
          imageUrl: null,
          source: "gbif" as const,
        };
      });

    let nextImageIndex = 0;
    const imageLookupCount = plants.length;
    const imageWorkers = Array.from(
      { length: Math.min(3, imageLookupCount) },
      async () => {
        while (nextImageIndex < imageLookupCount) {
          const index = nextImageIndex++;
          const plant = plants[index];
          if (!plant.acceptedTaxonId) continue;

          const [image, names] = await Promise.all([
            fetchImageForTaxon(plant.acceptedTaxonId),
            fetchLocalizedNamesByKey(plant.acceptedTaxonId),
          ]);
          if (image) Object.assign(plant, image);
          Object.assign(plant, names);
        }
      },
    );
    await Promise.all(imageWorkers);

    return jsonResponse({
      success: true,
      source: "GBIF",
      results: plants,
    });
  } catch (error) {
    console.error(
      "GBIF search failed:",
      error instanceof Error ? error.name : "unknown error",
    );
    return jsonResponse(
      { error: { code: "plant_catalog_unavailable" } },
      502,
    );
  }
}

Deno.serve(async (request: Request): Promise<Response> => {
  try {
    return await handleRequest(request);
  } catch (error) {
    console.error(
      "Plant catalog handler failed:",
      error instanceof Error ? error.name : "unknown error",
    );
    return jsonResponse(
      { error: { code: "plant_catalog_unavailable" } },
      500,
    );
  }
});
