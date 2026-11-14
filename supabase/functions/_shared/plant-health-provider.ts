const PLANT_HEALTH_URL = "https://plant.id/api/v3/health_assessment";
const PLANT_HEALTH_DETAILS = [
  "local_name",
  "description",
  "treatment",
  "cause",
].join(",");

export function createPlantHealthRequest(
  imageBase64: string,
  apiKey: string,
): { url: string; init: RequestInit } {
  const url = new URL(PLANT_HEALTH_URL);
  url.searchParams.set("details", PLANT_HEALTH_DETAILS);

  return {
    url: url.toString(),
    init: {
      method: "POST",
      headers: {
        "Api-Key": apiKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ images: [imageBase64] }),
    },
  };
}
