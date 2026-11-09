import {
  authenticate,
  enforceRequestLimit,
  preflight,
  reply,
} from "../_shared/common.ts";
import { readFormData } from "../_shared/http.ts";

Deno.serve(async (request: Request) => {
  const options = preflight(request);
  if (options) return options;
  if (request.method !== "POST") {
    return reply({ error: "Method not allowed" }, 405);
  }

  const auth = await authenticate(request);
  if (auth instanceof Response) return auth;
  const limited = await enforceRequestLimit(auth.uid, "plant-identify", 15);
  if (limited) return limited;

  const key = Deno.env.get("PLANTNET_API_KEY");
  if (!key) return reply({ error: "Pl@ntNet is not configured" }, 503);

  const parsedForm = await readFormData(request, 8_100_000);
  if ("response" in parsedForm) return parsedForm.response;
  const form = parsedForm.form;
  const photo = form?.get("image");
  if (
    !(photo instanceof File) ||
    !["image/jpeg", "image/png"].includes(photo.type) ||
    photo.size > 8_000_000 ||
    photo.size === 0
  ) {
    return reply({ error: "JPEG or PNG up to 8 MB required" }, 400);
  }
  const organValue = form?.get("organ");
  const organ = typeof organValue === "string" ? organValue : "auto";
  if (!["auto", "leaf", "flower", "fruit", "bark"].includes(organ)) {
    return reply({ error: "Invalid organ" }, 400);
  }

  const providerRequest = new FormData();
  providerRequest.append("images", photo);
  providerRequest.append("organs", organ);
  try {
    const response = await fetch(
      `https://my-api.plantnet.org/v2/identify/all?api-key=${
        encodeURIComponent(key)
      }`,
      {
        method: "POST",
        body: providerRequest,
        signal: AbortSignal.timeout(25_000),
      },
    );
    if (!response.ok) {
      return reply(
        {
          error: response.status === 429
            ? "Identification quota reached"
            : "Identification provider unavailable",
        },
        response.status === 429 ? 429 : 502,
      );
    }

    const payload = await response.json();
    const matches = (Array.isArray(payload.results) ? payload.results : [])
      .slice(0, 5)
      .flatMap((item: Record<string, unknown>) => {
        const species = item.species;
        if (!species || typeof species !== "object") return [];
        const record = species as Record<string, unknown>;
        const scientificName = record.scientificNameWithoutAuthor;
        if (typeof scientificName !== "string" || !scientificName.trim()) {
          return [];
        }
        return [{
          scientific_name: scientificName.trim(),
          common_names: Array.isArray(record.commonNames)
            ? record.commonNames.filter((name: unknown) =>
              typeof name === "string"
            )
            : [],
          score: typeof item.score === "number" ? item.score : null,
        }];
      });

    if (matches.length === 0) {
      return reply({ error: "No plant identification was returned" }, 422);
    }

    const { data: history, error } = await auth.admin
      .from("plant_identifications")
      .insert({
        owner_id: auth.uid,
        status: "completed",
        provider: "plantnet",
        result: { matches },
      })
      .select("id")
      .single();
    if (error) {
      console.error("Identification history save failed:", error.code);
      return reply({ error: "Could not save identification history" }, 500);
    }

    return reply({ id: history.id, matches, source: "Pl@ntNet" });
  } catch (error) {
    console.error(
      "Plant identification failed:",
      error instanceof Error ? error.name : "unknown error",
    );
    return reply({ error: "Identification unavailable" }, 502);
  }
});
