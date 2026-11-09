import { corsHeaders, jsonResponse } from "../_shared/http.ts";

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  return jsonResponse({
    error: {
      code: "email_payment_review_required",
      message:
        "Payment decisions are available only through the secure email action.",
    },
  }, 410);
});
