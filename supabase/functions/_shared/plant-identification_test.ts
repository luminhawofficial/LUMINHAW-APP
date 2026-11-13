import { bestPlantIdentificationSuggestion } from "./plant-identification.ts";

Deno.test("selects the named plant suggestion with the highest valid score", () => {
  const first = { name: "First plant", probability: 0.41 };
  const best = { name: "Best plant", probability: 0.87 };
  const selected = bestPlantIdentificationSuggestion([
    first,
    { name: "Invalid score", probability: 1.4 },
    best,
    null,
  ]);
  if (selected !== best) {
    throw new Error("The strongest valid identification was not selected.");
  }
});

Deno.test("keeps the first named suggestion when scores are unavailable", () => {
  const first = { name: "First plant", probability: 1.4 };
  const selected = bestPlantIdentificationSuggestion([
    first,
    { name: "Second plant", probability: -0.1 },
  ]);
  if (selected !== first) {
    throw new Error("The first validly named suggestion should be retained.");
  }
});

Deno.test("ignores candidates without a scientific or common name", () => {
  const selected = bestPlantIdentificationSuggestion([
    { probability: 0.99 },
    { name: "Named plant", probability: 0.4 },
  ]);
  if (selected?.name !== "Named plant") {
    throw new Error("A nameless candidate was selected.");
  }
});
