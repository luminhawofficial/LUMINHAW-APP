export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function jsonResponse(
  body: unknown,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

export async function readJsonBody(
  request: Request,
  maxBytes = 15 * 1024 * 1024,
): Promise<{ body: Record<string, unknown> } | { response: Response }> {
  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > maxBytes) {
    return {
      response: jsonResponse(
        { error: { code: "request_too_large" } },
        413,
      ),
    };
  }

  const reader = request.body?.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  if (reader) {
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        totalBytes += value.byteLength;
        if (totalBytes > maxBytes) {
          await reader.cancel();
          return {
            response: jsonResponse(
              { error: { code: "request_too_large" } },
              413,
            ),
          };
        }
        chunks.push(value);
      }
    } finally {
      reader.releaseLock();
    }
  }

  const bodyBytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bodyBytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  const rawBody = new TextDecoder().decode(bodyBytes);

  let body: unknown;
  try {
    body = JSON.parse(rawBody);
  } catch (error) {
    if (error instanceof SyntaxError) {
      return {
        response: jsonResponse(
          { error: { code: "invalid_json" } },
          400,
        ),
      };
    }
    throw error;
  }

  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return {
      response: jsonResponse(
        { error: { code: "invalid_request_body" } },
        400,
      ),
    };
  }

  return { body: body as Record<string, unknown> };
}

export async function readFormData(
  request: Request,
  maxBytes: number,
): Promise<{ form: FormData } | { response: Response }> {
  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > maxBytes) {
    return {
      response: jsonResponse({ error: { code: "request_too_large" } }, 413),
    };
  }

  const reader = request.body?.getReader();
  const chunks: Uint8Array[] = [];
  let totalBytes = 0;
  if (reader) {
    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        totalBytes += value.byteLength;
        if (totalBytes > maxBytes) {
          await reader.cancel();
          return {
            response: jsonResponse(
              { error: { code: "request_too_large" } },
              413,
            ),
          };
        }
        chunks.push(value);
      }
    } finally {
      reader.releaseLock();
    }
  }

  const bytes = new Uint8Array(totalBytes);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  const headers = new Headers(request.headers);
  headers.delete("content-length");
  try {
    const boundedRequest = new Request(request.url, {
      method: "POST",
      headers,
      body: bytes,
    });
    return { form: await boundedRequest.formData() };
  } catch (error) {
    if (error instanceof TypeError || error instanceof SyntaxError) {
      return {
        response: jsonResponse(
          { error: { code: "invalid_multipart_form_data" } },
          400,
        ),
      };
    }
    throw error;
  }
}

function imagePayloadFrom(
  body: Record<string, unknown>,
): { base64: string; mimeType: string } | null {
  const image = body.imageBase64;
  if (typeof image !== "string" || image.length === 0) return null;

  const dataUriMatch = image.match(
    /^data:image\/(?:jpeg|png|webp);base64,([A-Za-z0-9+/=\r\n]+)$/i,
  );
  const encoded = dataUriMatch?.[1] ?? image;
  const normalized = encoded.replace(/\s/g, "");
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(normalized)) return null;

  try {
    const bytes = atob(normalized);
    if (bytes.length === 0 || bytes.length > 10 * 1024 * 1024) return null;
    const isPng = bytes.length >= 8 &&
      bytes.charCodeAt(0) === 0x89 &&
      bytes.charCodeAt(1) === 0x50 &&
      bytes.charCodeAt(2) === 0x4e &&
      bytes.charCodeAt(3) === 0x47;
    const isJpeg = bytes.length >= 3 &&
      bytes.charCodeAt(0) === 0xff &&
      bytes.charCodeAt(1) === 0xd8 &&
      bytes.charCodeAt(2) === 0xff;
    const isWebp = bytes.length >= 12 &&
      bytes.slice(0, 4) === "RIFF" &&
      bytes.slice(8, 12) === "WEBP";
    if (isPng) return { base64: normalized, mimeType: "image/png" };
    if (isJpeg) return { base64: normalized, mimeType: "image/jpeg" };
    if (isWebp) return { base64: normalized, mimeType: "image/webp" };
    return null;
  } catch (error) {
    if (error instanceof DOMException) return null;
    throw error;
  }
}

export function imageBase64From(body: Record<string, unknown>): string | null {
  return imagePayloadFrom(body)?.base64 ?? null;
}

export function imageDataUriFrom(body: Record<string, unknown>): string | null {
  const image = imagePayloadFrom(body);
  return image === null
    ? null
    : `data:${image.mimeType};base64,${image.base64}`;
}
