import {
  isResponse,
  isUuid,
  paymentServiceClient,
  paymentUser,
} from "../_shared/payments.ts";
import { corsHeaders, jsonResponse, readJsonBody } from "../_shared/http.ts";

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: { code: "method_not_allowed" } }, 405);
  }

  const userId = await paymentUser(request, "cancel-premium-payment", 5, 3600);
  if (userId instanceof Response) return userId;
  const parsed = await readJsonBody(request, 4096);
  if ("response" in parsed) return parsed.response;

  const requestId = parsed.body.requestId;
  if (!isUuid(requestId)) {
    return jsonResponse({ error: { code: "invalid_payment_request" } }, 400);
  }

  const client = paymentServiceClient();
  if (isResponse(client)) return client;
  const { data, error } = await client.rpc(
    "cancel_pending_premium_payment_request",
    {
      p_user_id: userId,
      p_payment_request_id: requestId,
    },
  );
  if (error) {
    console.error("Payment request cancellation failed:", error.code);
    return jsonResponse(
      { error: { code: "payment_service_unavailable" } },
      503,
    );
  }
  if (data !== true) {
    return jsonResponse(
      { error: { code: "payment_request_not_cancellable" } },
      409,
    );
  }

  return jsonResponse({ cancelled: true });
});
