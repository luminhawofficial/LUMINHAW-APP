import { providerJson } from "./providers.ts";

Deno.test("providerJson retries safe GETs after transient status failures", async () => {
  let calls = 0;
  const result = await providerJson(
    "https://provider.example/species",
    {},
    1_000,
    async () => {
      calls++;
      return calls === 1
        ? new Response("", { status: 503 })
        : Response.json({ results: [] });
    },
  );

  if (calls !== 2 || !Array.isArray(result.results)) {
    throw new Error("Expected one retry followed by a valid response.");
  }
});

Deno.test("providerJson does not retry non-idempotent POSTs", async () => {
  let calls = 0;
  try {
    await providerJson(
      "https://provider.example/identify",
      { method: "POST" },
      1_000,
      async () => {
        calls++;
        return new Response("", { status: 429 });
      },
    );
    throw new Error("Expected the provider request to fail.");
  } catch (error) {
    if (!(error instanceof Error) || error.message !== "Provider HTTP 429") {
      throw error;
    }
  }
  if (calls !== 1) throw new Error("POST provider requests must not retry.");
});

Deno.test("providerJson retries transient network failures", async () => {
  let calls = 0;
  const result = await providerJson(
    "https://provider.example/species",
    {},
    1_000,
    async () => {
      calls++;
      if (calls === 1) throw new TypeError("network unavailable");
      return Response.json({ ok: true });
    },
  );

  if (calls !== 2 || result.ok !== true) {
    throw new Error("Expected a transient GET failure to be retried.");
  }
});

Deno.test("providerJson retries timed-out safe GETs", async () => {
  let calls = 0;
  const result = await providerJson(
    "https://provider.example/species",
    {},
    1,
    async () => {
      calls++;
      if (calls === 1) {
        throw new DOMException("Request timed out", "TimeoutError");
      }
      return Response.json({ ok: true });
    },
  );

  if (calls !== 2 || result.ok !== true) {
    throw new Error("Expected a timed-out GET to be retried.");
  }
});

Deno.test("providerJson reports malformed JSON without leaking response data", async () => {
  try {
    await providerJson(
      "https://provider.example/species",
      {},
      1_000,
      async () => new Response("{invalid"),
    );
    throw new Error("Expected malformed provider JSON to fail.");
  } catch (error) {
    if (
      !(error instanceof Error) ||
      error.message !== "Provider returned invalid JSON."
    ) {
      throw error;
    }
  }
});

Deno.test("providerJson handles authorization, not-found, and provider failures", async () => {
  for (const status of [403, 404, 429, 503]) {
    let calls = 0;
    try {
      await providerJson(
        "https://provider.example/species",
        {},
        1_000,
        async () => {
          calls++;
          return new Response("", { status });
        },
      );
      throw new Error(`Expected provider HTTP ${status} to fail.`);
    } catch (error) {
      if (
        !(error instanceof Error) || error.message !== `Provider HTTP ${status}`
      ) {
        throw error;
      }
    }
    const expectedCalls = [429, 503].includes(status) ? 3 : 1;
    if (calls !== expectedCalls) {
      throw new Error(`Unexpected retry count for HTTP ${status}.`);
    }
  }
});
