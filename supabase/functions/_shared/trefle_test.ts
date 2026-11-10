import {
  findExactTreflePlant,
  parseTrefleSearchResponse,
  searchTreflePlants,
} from "./trefle.ts";

Deno.test("Trefle search keeps accepted species and maps taxonomy", () => {
  const plants = parseTrefleSearchResponse({
    data: [
      {
        scientific_name: "Monstera deliciosa",
        common_name: "Swiss cheese plant",
        family: "Araceae",
        genus: "Monstera",
        rank: "species",
        status: "accepted",
        slug: "monstera-deliciosa",
      },
      {
        scientific_name: "Monstera",
        rank: "genus",
        status: "accepted",
      },
      {
        scientific_name: "Monstera deliciosa synonym",
        rank: "species",
        status: "synonym",
      },
    ],
  });

  if (
    plants.length !== 1 ||
    plants[0].scientificName !== "Monstera deliciosa" ||
    plants[0].family !== "Araceae" ||
    plants[0].genus !== "Monstera" ||
    plants[0].slug !== "monstera-deliciosa"
  ) {
    throw new Error("Trefle accepted species were not mapped correctly.");
  }
});

Deno.test("Trefle enrichment requires an exact normalized species match", () => {
  const plants = parseTrefleSearchResponse({
    data: [
      { scientific_name: "Monstera", rank: "species", status: "accepted" },
      {
        scientific_name: " Monstera   deliciosa ",
        family: "Araceae",
        rank: "species",
        status: "accepted",
      },
    ],
  });
  const match = findExactTreflePlant(plants, "monstera deliciosa");

  if (match?.family !== "Araceae") {
    throw new Error(
      "Trefle accepted a partial rather than exact species match.",
    );
  }
});

Deno.test("Trefle search sends query and token to its server API", async () => {
  let requestUrl: URL | undefined;
  const plants = await searchTreflePlants(
    "Monstera deliciosa",
    "test-token",
    async (input) => {
      requestUrl = new URL(String(input));
      return Response.json({
        data: [{
          scientific_name: "Monstera deliciosa",
          rank: "species",
          status: "accepted",
        }],
      });
    },
  );

  if (
    requestUrl?.origin !== "https://trefle.io" ||
    requestUrl.pathname !== "/api/v1/plants/search" ||
    requestUrl.searchParams.get("q") !== "Monstera deliciosa" ||
    requestUrl.searchParams.get("token") !== "test-token" ||
    plants.length !== 1
  ) {
    throw new Error("Trefle request was not configured correctly.");
  }
});
