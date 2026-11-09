import { imageBase64From, readFormData, readJsonBody } from "./http.ts";
import { authenticatedUserId } from "./auth.ts";

Deno.test("readJsonBody rejects malformed JSON", async () => {
  const parsed = await readJsonBody(
    new Request("https://local.test", { method: "POST", body: "{" }),
  );
  if (!("response" in parsed) || parsed.response.status !== 400) {
    throw new Error("Malformed JSON should return HTTP 400.");
  }
});

Deno.test("readJsonBody rejects oversized bodies", async () => {
  const parsed = await readJsonBody(
    new Request("https://local.test", {
      method: "POST",
      body: '{"payload":"large"}',
    }),
    4,
  );
  if (!("response" in parsed) || parsed.response.status !== 413) {
    throw new Error("Oversized requests should return HTTP 413.");
  }
});

Deno.test("readFormData enforces its limit before multipart parsing", async () => {
  const request = new Request("https://local.test", {
    method: "POST",
    body: new Uint8Array(32),
    headers: { "content-type": "multipart/form-data; boundary=unused" },
  });
  const parsed = await readFormData(request, 16);
  if (!("response" in parsed) || parsed.response.status !== 413) {
    throw new Error("Oversized multipart requests should return HTTP 413.");
  }
});

Deno.test("readFormData rejects malformed multipart content", async () => {
  const request = new Request("https://local.test", {
    method: "POST",
    body: "not multipart data",
    headers: { "content-type": "multipart/form-data; boundary=broken" },
  });
  const parsed = await readFormData(request, 1_000);
  if (!("response" in parsed) || parsed.response.status !== 400) {
    throw new Error("Malformed multipart requests should return HTTP 400.");
  }
});

Deno.test("readFormData returns parsed forms for bounded requests", async () => {
  const form = new FormData();
  form.append("organ", "leaf");
  const parsed = await readFormData(
    new Request("https://local.test", { method: "POST", body: form }),
    1_000,
  );
  if (!("form" in parsed) || parsed.form.get("organ") !== "leaf") {
    throw new Error("Expected the bounded form data to be parsed.");
  }
});

Deno.test("authenticatedUserId rejects a missing bearer token", async () => {
  const response = await authenticatedUserId(
    new Request("https://local.test", { method: "POST" }),
  );
  if (!(response instanceof Response) || response.status !== 401) {
    throw new Error("Missing credentials should return HTTP 401.");
  }
});

Deno.test("imageBase64From rejects absent or malformed images", () => {
  if (imageBase64From({}) !== null) {
    throw new Error("Missing images must be rejected.");
  }
  if (imageBase64From({ imageBase64: "not-an-image" }) !== null) {
    throw new Error("Malformed image payloads must be rejected.");
  }
});

Deno.test("imageBase64From accepts a valid PNG signature", () => {
  const bytes = Uint8Array.from([
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
    0x00,
    0x00,
    0x00,
    0x00,
  ]);
  const encoded = btoa(String.fromCharCode(...bytes));
  if (imageBase64From({ imageBase64: encoded }) !== encoded) {
    throw new Error("A valid PNG image should be accepted.");
  }
});
