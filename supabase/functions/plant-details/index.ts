import {
  authenticate,
  enforceRequestLimit,
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
  const limited = await enforceRequestLimit(auth.uid, "plant-details", 120);
  if (limited) return limited;

  const id = new URL(request.url).searchParams.get("id");
  if (!id || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) {
    return reply({error: "Valid UUID id required"}, 400);
  }

  const {data, error} = await auth.admin
    .from("plant_catalog")
    .select("*,plant_images(*)")
    .eq("id", id)
    .maybeSingle();
  if (error) {
    console.error("Plant details query failed:", error.code);
    return reply({error: "Database unavailable"}, 500);
  }
  if (!data) return reply({error: "Plant not found"}, 404);

  const {data: care, error: careError} = await auth.admin
    .from("plant_care")
    .select("*")
    .eq("plant_id", id)
    .eq("reviewed", true)
    .maybeSingle();
  if (careError) {
    console.error("Plant care query failed:", careError.code);
    return reply({error: "Database unavailable"}, 500);
  }
  return reply({plant: {...data, plant_care: care}});
});
