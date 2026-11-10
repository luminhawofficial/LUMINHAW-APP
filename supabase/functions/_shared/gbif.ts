export type GbifSpecies = {
  key: string;
  scientificName?: string;
  rank: string;
  taxonomicStatus: string;
  confidence: number;
  kingdom?: string;
  phylum?: string;
  taxonomicClass?: string;
  order?: string;
  family?: string;
  genus?: string;
  species?: string;
};

export type GbifImage = {
  imageUrl: string;
  imageAttribution?: string;
  imageLicense: string;
  imageLicenseUrl: string;
  imageReferenceUrl: string;
};

export type GbifLocalizedNames = {
  tagalogName?: string;
  bisayaName?: string;
};

function object(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function text(value: unknown): string | undefined {
  if (typeof value === "string" && value.trim()) return value.trim();
  if (Array.isArray(value)) {
    for (const item of value) {
      if (typeof item === "string" && item.trim()) return item.trim();
    }
  }
  return undefined;
}

function normalizedName(value: string): string {
  return value.trim().replace(/\s+/g, " ").toLowerCase();
}

function httpsUrl(value: unknown): string | undefined {
  const candidate = text(value);
  if (!candidate) return undefined;
  try {
    const url = new URL(candidate);
    return url.protocol === "https:" ? url.toString() : undefined;
  } catch {
    return undefined;
  }
}

function reusableLicense(value: unknown): {
  name: string;
  url: string;
} | undefined {
  const license = text(value);
  if (!license) return undefined;

  const normalized = license.toLowerCase().replaceAll("_", "-")
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
  if (!version) return undefined;

  return {
    name: `CC BY ${version}.0`,
    url: `https://creativecommons.org/licenses/by/${version}.0/`,
  };
}

export function parseGbifSpeciesMatch(
  payload: unknown,
  requestedName: string,
): GbifSpecies | undefined {
  const match = object(payload);
  if (
    typeof match?.usageKey !== "number" ||
    match.status !== "ACCEPTED" ||
    match.rank !== "SPECIES" ||
    typeof match.confidence !== "number" ||
    match.confidence < 80
  ) return undefined;

  const canonicalName = text(match.canonicalName);
  const scientificName = text(match.scientificName);
  const expected = normalizedName(requestedName);
  if (
    expected !== normalizedName(canonicalName ?? "") &&
    expected !== normalizedName(scientificName ?? "")
  ) return undefined;

  return {
    key: String(match.usageKey),
    scientificName,
    rank: "SPECIES",
    taxonomicStatus: "ACCEPTED",
    confidence: match.confidence,
    kingdom: text(match.kingdom),
    phylum: text(match.phylum),
    taxonomicClass: text(match.class),
    order: text(match.order),
    family: text(match.family),
    genus: text(match.genus),
    species: text(match.species),
  };
}

export async function findGbifSpeciesMatch(
  scientificName: string,
  fetcher: typeof fetch = fetch,
): Promise<GbifSpecies | undefined> {
  const url = new URL("https://api.gbif.org/v1/species/match");
  url.searchParams.set("name", scientificName);
  url.searchParams.set("rank", "SPECIES");
  url.searchParams.set("kingdom", "Plantae");
  const response = await fetcher(url, { signal: AbortSignal.timeout(5_000) });
  if (!response.ok) return undefined;
  return parseGbifSpeciesMatch(await response.json(), scientificName);
}

export function parseGbifLocalizedNames(payload: unknown): GbifLocalizedNames {
  const results = object(payload)?.results;
  if (!Array.isArray(results)) return {};

  const names: GbifLocalizedNames = {};
  for (const item of results) {
    const record = object(item);
    const name = text(record?.vernacularName);
    const language = text(record?.language)?.toLowerCase().split(/[-_]/)[0];
    if (!name || !language) continue;
    if ((language === "tgl" || language === "fil") && !names.tagalogName) {
      names.tagalogName = name;
    }
    if (language === "ceb" && !names.bisayaName) {
      names.bisayaName = name;
    }
  }
  return names;
}

export async function findGbifOccurrenceImage(
  taxonKey: string,
  fetcher: typeof fetch = fetch,
): Promise<GbifImage | undefined> {
  const url = new URL("https://api.gbif.org/v1/occurrence/search");
  url.searchParams.set("taxon_key", taxonKey);
  url.searchParams.set("media_type", "StillImage");
  for (const license of ["CC0_1_0", "CC_BY_4_0"]) {
    url.searchParams.append("license", license);
  }
  url.searchParams.set("limit", "10");

  const response = await fetcher(url, { signal: AbortSignal.timeout(8_000) });
  if (!response.ok) return undefined;
  const results = object(await response.json())?.results;
  if (!Array.isArray(results)) return undefined;

  for (const item of results) {
    const occurrence = object(item);
    if (!Array.isArray(occurrence?.media)) continue;
    const occurrenceKey = typeof occurrence.key === "number"
      ? String(occurrence.key)
      : undefined;
    const occurrencePage = occurrenceKey
      ? `https://www.gbif.org/occurrence/${occurrenceKey}`
      : undefined;

    for (const mediaItem of occurrence.media) {
      const media = object(mediaItem);
      if (!media) continue;
      if (
        media.type != null &&
        (typeof media.type !== "string" ||
          media.type.toLowerCase() !== "stillimage")
      ) continue;
      const imageUrl = httpsUrl(media?.identifier);
      const license = reusableLicense(media?.license);
      if (!imageUrl || !license) continue;

      const imageAttribution = text(media.creator) ??
        text(media.rightsHolder) ??
        text(media.publisher);
      if (license.name !== "CC0 1.0" && !imageAttribution) continue;

      return {
        imageUrl,
        imageAttribution,
        imageLicense: license.name,
        imageLicenseUrl: license.url,
        imageReferenceUrl: httpsUrl(media.references) ?? occurrencePage ??
          imageUrl,
      };
    }
  }
  return undefined;
}
