import {
  authenticate,
  enforceRequestLimit,
  preflight,
  reply,
  requirePremium,
} from "../_shared/common.ts";
import {
  boundedText,
  providerJson,
  requiredSecret,
} from "../_shared/providers.ts";

Deno.serve(async (request: Request) => {
  const options = preflight(request);
  if (options) return options;
  if (request.method !== "POST") {
    return reply({ error: "Method not allowed" }, 405);
  }

  const auth = await authenticate(request);
  if (auth instanceof Response) return auth;
  const limited = await enforceRequestLimit(auth.uid, "plant-gemini", 30);
  if (limited) return limited;
  const premiumRequired = await requirePremium(auth.uid);
  if (premiumRequired) return premiumRequired;

  const body = await request.json().catch(() => null);
  const question = boundedText(
    body && typeof body === "object"
      ? (body as Record<string, unknown>).question
      : null,
    1000,
  );
  if (question.length < 3) {
    return reply({ error: "question must contain at least 3 characters" }, 400);
  }

  let key: string;
  try {
    key = requiredSecret("GEMINI_API_KEY");
  } catch {
    return reply({ error: "Gemini is not configured" }, 503);
  }

  try {
    const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
    const result = await providerJson(
      `https://generativelanguage.googleapis.com/v1beta/models/${
        encodeURIComponent(model)
      }:generateContent`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": key,
        },
        body: JSON.stringify({
          systemInstruction: {
            parts: [{
              text:
                "You are LUMINHAW, a cautious plant-care assistant. Do not invent species identification or imply certainty. Explain uncertainty. Do not recommend unsafe pesticide mixing or consumption of unknown plants.",
            }],
          },
          contents: [{ role: "user", parts: [{ text: question }] }],
          generationConfig: { maxOutputTokens: 700 },
        }),
      },
      25_000,
    );
    const parts = result.candidates?.[0]?.content?.parts;
    const answer = Array.isArray(parts)
      ? parts.map((part: Record<string, unknown>) =>
        typeof part.text === "string" ? part.text : ""
      ).join("").trim()
      : "";
    if (!answer) return reply({ error: "Gemini returned no answer" }, 502);
    return reply({ source: "Gemini", answer });
  } catch (error) {
    console.error(
      "Gemini request failed:",
      error instanceof Error ? error.name : "unknown error",
    );
    return reply({ error: "AI assistant unavailable" }, 502);
  }
});
