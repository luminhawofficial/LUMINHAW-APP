import { parseAdminPlantCatalogInput } from "./plant-catalog-input.ts";

const validBody = {
  common_name: "Kangkong",
  scientific_name: "Ipomoea aquatica",
  date_updated: "2026-11-13",
  field_references: {
    common_name: ["Department of Agriculture"],
    scientific_name: ["https://example.org/flora"],
  },
};

Deno.test("parses a sourced plant record", () => {
  const result = parseAdminPlantCatalogInput(validBody, false);
  if (!result.ok) {
    throw new Error(`Unexpected validation failure: ${result.code}`);
  }
  if (result.value.catalog.common_name !== "Kangkong") {
    throw new Error("Common name was not preserved.");
  }
  if (result.value.care.toxicity !== "unknown") {
    throw new Error("Unset toxicity must remain unknown.");
  }
  if (
    result.value.fieldReferences.scientific_name[0] !==
      "https://example.org/flora"
  ) {
    throw new Error("Scientific-name reference was not preserved.");
  }
});

Deno.test("requires a source for every populated fact", () => {
  const result = parseAdminPlantCatalogInput({
    ...validBody,
    tagalog_name: "Kangkong",
  }, false);
  if (result.ok || result.code !== "plant_reference_required") {
    throw new Error("A missing Tagalog-name source must be rejected.");
  }
});

Deno.test("allows unknown toxicity without a citation", () => {
  const result = parseAdminPlantCatalogInput({
    ...validBody,
    toxicity: "unknown",
  }, false);
  if (!result.ok) {
    throw new Error(`Unexpected validation failure: ${result.code}`);
  }
});

Deno.test("rejects insecure image URLs and invalid dates", () => {
  const insecureImage = parseAdminPlantCatalogInput({
    ...validBody,
    image_url: "http://example.org/plant.jpg",
    field_references: {
      ...validBody.field_references,
      image_url: ["https://example.org/source"],
    },
  }, false);
  const invalidDate = parseAdminPlantCatalogInput({
    ...validBody,
    date_updated: "2026-02-30",
  }, false);
  if (
    insecureImage.ok || insecureImage.code !== "invalid_plant_catalog_record"
  ) {
    throw new Error("An insecure image URL must be rejected.");
  }
  if (invalidDate.ok || invalidDate.code !== "invalid_plant_catalog_record") {
    throw new Error("An invalid calendar date must be rejected.");
  }
});

Deno.test("requires a UUID when updating a plant", () => {
  const result = parseAdminPlantCatalogInput({
    ...validBody,
    id: "not-a-uuid",
  }, true);
  if (result.ok || result.code !== "invalid_plant_catalog_record") {
    throw new Error("An invalid update ID must be rejected.");
  }
});
