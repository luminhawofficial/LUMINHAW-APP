export function bestPlantIdentificationSuggestion(
  suggestions: unknown[],
): Record<string, unknown> | undefined {
  let best: Record<string, unknown> | undefined;
  let bestProbability = -1;

  for (const item of suggestions) {
    if (item === null || typeof item !== "object" || Array.isArray(item)) {
      continue;
    }
    const candidate = item as Record<string, unknown>;
    const details = candidate.details !== null &&
        typeof candidate.details === "object" &&
        !Array.isArray(candidate.details)
      ? candidate.details as Record<string, unknown>
      : undefined;
    const hasName = typeof candidate.name === "string" &&
      candidate.name.trim().length > 0;
    const hasScientificName = typeof details?.scientific_name === "string" &&
      details.scientific_name.trim().length > 0;
    if (!hasName && !hasScientificName) continue;

    const probability = candidate.probability;
    const score = typeof probability === "number" &&
        Number.isFinite(probability) &&
        probability >= 0 &&
        probability <= 1
      ? probability
      : -1;
    if (!best || score > bestProbability) {
      best = candidate;
      bestProbability = score;
    }
  }
  return best;
}
