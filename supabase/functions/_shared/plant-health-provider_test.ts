import { createPlantHealthRequest } from "./plant-health-provider.ts";

Deno.test("Plant.ID health request uses query details and plain Base64 images", async () => {
  const imageBase64 = "iVBORw0KGgo=";
  const request = createPlantHealthRequest(imageBase64, "test-api-key");
  const url = new URL(request.url);
  const body = JSON.parse(String(request.init.body));

  if (url.pathname !== "/api/v3/health_assessment") {
    throw new Error("Expected the Plant.ID health-assessment endpoint.");
  }
  if (
    url.searchParams.get("details") !==
      "local_name,description,treatment,cause"
  ) {
    throw new Error("Health details must be sent as a query parameter.");
  }
  if (body.details !== undefined) {
    throw new Error("Health details must not be sent in the JSON body.");
  }
  if (
    !Array.isArray(body.images) ||
    body.images.length !== 1 ||
    body.images[0] !== imageBase64
  ) {
    throw new Error("Expected a single plain Base64 image in the JSON body.");
  }
  if (
    (request.init.headers as Record<string, string>)["Api-Key"] !==
      "test-api-key"
  ) {
    throw new Error("Expected the Plant.ID API key header.");
  }
});
