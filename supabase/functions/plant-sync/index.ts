import {
  authenticate,
  enforceRequestLimit,
  gbif,
  preflight,
  reply,
} from "../_shared/common.ts";

Deno.serve(async (request: Request) => {
  const options = preflight(request);
  if (options) return options;
  if (request.method !== "POST") {
    return reply({error: "Method not allowed"}, 405);
  }

  const auth = await authenticate(request);
  if (auth instanceof Response) return auth;
  const limited = await enforceRequestLimit(auth.uid, "plant-sync", 20);
  if (limited) return limited;

  const body = await request.json().catch(() => null);
  const key = body && typeof body === "object"
    ? Number((body as Record<string, unknown>).gbif_key)
    : NaN;
  if (!Number.isSafeInteger(key) || key <= 0) {
    return reply({error: "Valid gbif_key required"}, 400);
  }

  try {
    const taxon = await gbif(`species/${key}`);
    if (
      taxon.kingdom !== "Plantae" ||
      !taxon.canonicalName ||
      taxon.rank !== "SPECIES" ||
      taxon.taxonomicStatus !== "ACCEPTED"
    ) {
      return reply({error: "Not an accepted plant species"}, 422);
    }

    const record = {
      gbif_key: key,
      scientific_name: taxon.canonicalName,
      common_name: null,
      family: taxon.family ?? null,
      genus: taxon.genus ?? null,
    };
    const {data, error} = await auth.admin
      .from("plant_catalog")
      .upsert(record, {onConflict: "gbif_key"})
      .select()
      .single();
    if (error) throw error;
    return reply({plant: data, source: "GBIF"});
  } catch (error) {
    console.error(
      "Plant sync failed:",
      error instanceof Error ? error.name : "unknown error",
    );
    return reply({error: "Could not synchronize plant"}, 502);
  }
});
