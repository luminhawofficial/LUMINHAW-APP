import {
  findGbifOccurrenceImage,
  findGbifSpeciesMatch,
  parseGbifLocalizedNames,
  parseGbifSpeciesMatch,
} from "./gbif.ts";

Deno.test("GBIF accepts only confident exact accepted species matches", () => {
  const accepted = parseGbifSpeciesMatch({
    usageKey: 123,
    scientificName: "Rosa canina L.",
    canonicalName: "Rosa canina",
    rank: "SPECIES",
    status: "ACCEPTED",
    confidence: 99,
    family: "Rosaceae",
    genus: "Rosa",
    species: "canina",
  }, "Rosa canina");
  const partial = parseGbifSpeciesMatch({
    usageKey: 456,
    scientificName: "Rosa",
    canonicalName: "Rosa",
    rank: "SPECIES",
    status: "ACCEPTED",
    confidence: 99,
  }, "Rosa canina");
  const uncertain = parseGbifSpeciesMatch({
    usageKey: 789,
    scientificName: "Rosa canina",
    canonicalName: "Rosa canina",
    rank: "SPECIES",
    status: "ACCEPTED",
    confidence: 50,
  }, "Rosa canina");

  if (
    accepted?.key !== "123" ||
    accepted.family !== "Rosaceae" ||
    accepted.genus !== "Rosa" ||
    partial !== undefined ||
    uncertain !== undefined
  ) {
    throw new Error(
      "GBIF species matching did not enforce exact accepted names.",
    );
  }
});

Deno.test("GBIF species lookup uses the public taxonomy match endpoint", async () => {
  let requestUrl: URL | undefined;
  const match = await findGbifSpeciesMatch(
    "Rosa canina",
    async (input) => {
      requestUrl = new URL(String(input));
      return Response.json({
        usageKey: 123,
        scientificName: "Rosa canina",
        canonicalName: "Rosa canina",
        rank: "SPECIES",
        status: "ACCEPTED",
        confidence: 99,
      });
    },
  );
  if (
    requestUrl?.pathname !== "/v1/species/match" ||
    match?.key !== "123"
  ) {
    throw new Error("GBIF species lookup returned no accepted match.");
  }
});

Deno.test("GBIF localized names keep Tagalog and Cebuano vernacular names", () => {
  const names = parseGbifLocalizedNames({
    results: [
      { vernacularName: "Rosas", language: "fil" },
      { vernacularName: "Rosas Cebuano", language: "ceb" },
      { vernacularName: "Rose", language: "en" },
    ],
  });
  if (names.tagalogName !== "Rosas" || names.bisayaName !== "Rosas Cebuano") {
    throw new Error("GBIF localized names were not mapped correctly.");
  }
});

Deno.test("GBIF images require a secure reusable license and attribution", async () => {
  let calls = 0;
  const image = await findGbifOccurrenceImage("123", async () => {
    calls++;
    return Response.json({
      results: [{
        key: 789,
        media: [
          {
            type: "StillImage",
            identifier: "http://example.test/unsafe.jpg",
            license: "CC BY 4.0",
            creator: "Photographer",
          },
          {
            type: "StillImage",
            identifier: "https://example.test/unlicensed.jpg",
            license: "All rights reserved",
            creator: "Photographer",
          },
          {
            type: "StillImage",
            identifier: "https://example.test/rose.jpg",
            license: "CC BY 4.0",
            creator: "Photographer",
            references: "https://example.test/source",
          },
        ],
      }],
    });
  });

  if (
    calls !== 1 ||
    image?.imageUrl !== "https://example.test/rose.jpg" ||
    image.imageAttribution !== "Photographer" ||
    image.imageLicense !== "CC BY 4.0" ||
    image.imageReferenceUrl !== "https://example.test/source"
  ) {
    throw new Error("GBIF did not return a properly licensed image.");
  }
});
