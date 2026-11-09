export async function providerJson(
  url: string,
  init: RequestInit = {},
  timeout = 18_000,
  fetcher: typeof fetch = fetch,
) {
  const method = (init.method ?? "GET").toUpperCase();
  const retrySafe = method === "GET";
  let response: Response | undefined;

  for (let attempt = 0; attempt < (retrySafe ? 3 : 1); attempt++) {
    try {
      response = await fetcher(url, {
        ...init,
        signal: AbortSignal.timeout(timeout),
      });
    } catch (error) {
      if (attempt === (retrySafe ? 2 : 0)) throw error;
      await new Promise((resolve) => setTimeout(resolve, 200 * 2 ** attempt));
      continue;
    }

    const shouldRetry = retrySafe &&
      [429, 500, 502, 503, 504].includes(response.status) &&
      attempt < 2;
    if (!shouldRetry) break;

    const retryAfter = Number(response.headers.get("retry-after"));
    const delay = Number.isFinite(retryAfter) && retryAfter > 0
      ? Math.min(retryAfter * 1000, 2_000)
      : 200 * 2 ** attempt;
    await new Promise((resolve) => setTimeout(resolve, delay));
  }

  if (!response) throw new Error("Provider request failed.");
  if (!response.ok) { const text = await response.text().catch(() => ""); throw new Error(`Provider HTTP ${response.status}: ${text}`); }
  try {
    return await response.json();
  } catch (error) {
    if (error instanceof SyntaxError) {
      throw new Error("Provider returned invalid JSON.");
    }
    throw error;
  }
}

export function requiredSecret(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} not configured`);
  return value;
}
export function boundedText(input: unknown, max = 200) {
  return typeof input === "string" ? input.trim().slice(0, max) : "";
}
