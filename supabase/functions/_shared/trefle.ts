import { providerJson } from "./providers.ts";

export type TreflePlant = {
  scientificName: string;
  commonName?: string;
  family?: string;
  genus?: string;
  rank?: string;
  status?: string;
  slug?: string;
};

function normalizeName(value: string): string {
  return value.trim().replace(/\s+/g, " ").toLowerCase();
}

function object(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function text(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

export function parseTrefleSearchResponse(payload: unknown): TreflePlant[] {
  const data = object(payload);
  if (!Array.isArray(data?.data)) return [];

  return data.data.flatMap((item: unknown) => {
    const record = object(item);
    const scientificName = text(record?.scientific_name);
    const rank = text(record?.rank);
    const status = text(record?.status);
    if (
      !scientificName ||
      (rank && rank.toLowerCase() !== "species") ||
      (status && status.toLowerCase() !== "accepted")
    ) {
      return [];
    }

    return [{
      scientificName,
      commonName: text(record?.common_name),
      family: text(record?.family),
      genus: text(record?.genus),
      rank,
      status,
      slug: text(record?.slug),
    }];
  });
}

export function findExactTreflePlant(
  plants: readonly TreflePlant[],
  scientificName: string,
): TreflePlant | undefined {
  const expectedName = normalizeName(scientificName);
  return plants.find(
    (plant) => normalizeName(plant.scientificName) === expectedName,
  );
}

export async function searchTreflePlants(
  query: string,
  token: string,
  fetcher: typeof fetch = fetch,
): Promise<TreflePlant[]> {
  const url = new URL("https://trefle.io/api/v1/plants/search");
  url.searchParams.set("q", query);
  url.searchParams.set("token", token);
  const response = await providerJson(
    url.toString(),
    {},
    8_000,
    fetcher,
  );
  return parseTrefleSearchResponse(response);
}
