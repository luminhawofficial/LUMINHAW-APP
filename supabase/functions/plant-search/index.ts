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
  if (request.method !== "GET") {
    return reply({error: "Method not allowed"}, 405);
  }

  const auth = await authenticate(request);
  if (auth instanceof Response) return auth;
  const limited = await enforceRequestLimit(auth.uid, "plant-search", 60);
  if (limited) return limited;

  const query = (new URL(request.url).searchParams.get("q") ?? "").trim();
  if (query.length < 2 || query.length > 100) {
    return reply({error: "q must contain 2–100 characters"}, 400);
  }

  try {
    const pattern = `%${query.replace(/[\\%_]/g, "\\$&")}%`;
    const columns = "id,gbif_key,scientific_name,common_name,family";
    const [scientific, common] = await Promise.all([
      auth.admin.from("plant_catalog").select(columns)
        .ilike("scientific_name", pattern).limit(20),
      auth.admin.from("plant_catalog").select(columns)
        .ilike("common_name", pattern).limit(20),
    ]);
    if (scientific.error) throw scientific.error;
    if (common.error) throw common.error;

    const localPlants = new Map<string, Record<string, unknown>>();
    for (const plant of [...scientific.data, ...common.data]) {
      localPlants.set(plant.id, plant);
    }
    if (localPlants.size > 0) {
      return reply({
        plants: [...localPlants.values()].slice(0, 20),
        source: "catalog",
      });
    }

    const remote = await gbif(
      `species/search?q=${encodeURIComponent(query)}` +
        "&rank=SPECIES&status=ACCEPTED&limit=20",
    );
    const plants = (Array.isArray(remote.results) ? remote.results : [])
      .filter((plant: Record<string, unknown>) =>
        plant.kingdom === "Plantae" &&
        plant.rank === "SPECIES" &&
        plant.taxonomicStatus === "ACCEPTED" &&
        typeof plant.key === "number" &&
        typeof plant.scientificName === "string"
      )
      .map((plant: Record<string, unknown>) => ({
        gbif_key: plant.key,
        scientific_name: plant.canonicalName ?? plant.scientificName,
        common_name: null,
        family: plant.family ?? null,
      }));

    return reply({
      plants,
      source: "GBIF",
      note: "Remote search results are not saved automatically; use plant-sync.",
    });
  } catch (error) {
    console.error(
      "Plant search failed:",
      error instanceof Error ? error.name : "unknown error",
    );
    return reply({error: "Plant search unavailable"}, 502);
  }
});
