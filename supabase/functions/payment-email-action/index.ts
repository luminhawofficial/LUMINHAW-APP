import {
  isResponse,
  parseLuminhawAppUrl,
  paymentServiceClient,
} from "../_shared/payments.ts";
import { deliverPaymentNotification } from "../_shared/payment-email.ts";
import {
  hashPaymentEmailToken,
  isPaymentEmailActionTokenActive,
  isPaymentEmailToken,
} from "../_shared/payment-email-token.ts";

const reviewerEmail = "luminhawofficial@gmail.com";
const pageHeaders = {
  "content-type": "text/html; charset=utf-8",
  "cache-control": "no-store, max-age=0",
  "content-security-policy":
    "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
};
const jsonSecurityHeaders = {
  "cache-control": "no-store, max-age=0",
  "content-type": "application/json; charset=utf-8",
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
};

function isLuminhawOrigin(request: Request): boolean {
  const configuredUrl = parseLuminhawAppUrl(
    Deno.env.get("LUMINHAW_APP_URL"),
  );
  return configuredUrl !== null &&
    request.headers.get("origin") === configuredUrl.origin;
}

function jsonResponse(
  request: Request,
  body: Record<string, unknown>,
  status = 200,
): Response {
  const headers = new Headers(jsonSecurityHeaders);
  if (isLuminhawOrigin(request)) {
    headers.set("access-control-allow-origin", request.headers.get("origin")!);
    headers.set("vary", "Origin");
  }
  return Response.json(body, { status, headers });
}

function escapeHtml(value: unknown): string {
  return String(value ?? "").replace(/[&<>"']/g, (character) =>
    ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#39;",
    })[character]!);
}

function page(
  title: string,
  message: string,
  form = "",
  status = 200,
): Response {
  return new Response(
    `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${
      escapeHtml(title)
    }</title><style>body{font:16px system-ui,sans-serif;background:#eef7eb;color:#174d3c;margin:0;padding:24px}main{max-width:560px;margin:6vh auto;background:white;border-radius:16px;padding:24px;box-shadow:0 8px 32px #174d3c18}h1{font-size:1.5rem}button{background:#086044;color:white;border:0;border-radius:10px;padding:12px 18px;font:inherit;font-weight:700;cursor:pointer}textarea{box-sizing:border-box;width:100%;min-height:110px;margin:12px 0;padding:10px;font:inherit}label{display:block;margin:18px 0}small{color:#64776e}</style><main><h1>${
      escapeHtml(title)
    }</h1><p>${escapeHtml(message)}</p>${form}</main></html>`,
    { status, headers: pageHeaders },
  );
}

function invalidPage(): Response {
  return page(
    "Payment action unavailable",
    "This email action is invalid, expired, or has already been used. Request a new payment notification if needed.",
  );
}

function requestToken(request: Request, bodyToken?: string): string | null {
  const token = bodyToken ?? new URL(request.url).searchParams.get("token");
  return token && isPaymentEmailToken(token) ? token : null;
}

async function rateLimitKey(request: Request): Promise<string> {
  const address = request.headers.get("cf-connecting-ip") ??
    request.headers.get("x-real-ip") ??
    "unknown";
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`payment-email-action:${address}`),
  );
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

async function tokenRateLimitKey(tokenHash: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`payment-email-action:token:${tokenHash}`),
  );

  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    if (!isLuminhawOrigin(request)) {
      return new Response(null, { status: 403, headers: pageHeaders });
    }
    return new Response(null, {
      status: 204,
      headers: {
        ...jsonSecurityHeaders,
        "access-control-allow-origin": request.headers.get("origin")!,
        "access-control-allow-methods": "POST, OPTIONS",
        "access-control-allow-headers": "content-type",
        "access-control-max-age": "600",
        vary: "Origin",
      },
    });
  }
  const isJsonPost = request.method === "POST" &&
    request.headers.get("content-type")?.toLowerCase().includes(
        "application/json",
      ) === true;
  if (request.method !== "GET" && request.method !== "POST") {
    return new Response("Method not allowed", {
      status: 405,
      headers: {
        ...pageHeaders,
        allow: "GET, POST, OPTIONS",
      },
    });
  }
  if (isJsonPost && !isLuminhawOrigin(request)) {
    return jsonResponse(request, { error: "origin_not_allowed" }, 403);
  }
  const client = paymentServiceClient();
  if (isResponse(client)) {
    return page(
      "Payment action unavailable",
      "The payment service is temporarily unavailable. Please try again later.",
      "",
      client.status,
    );
  }
  const { data: rateAllowed, error: rateError } = await client.rpc(
    "consume_payment_email_action_rate_limit",
    {
      p_rate_key: await rateLimitKey(request),
      p_limit: 60,
      p_window_seconds: 600,
    },
  );
  if (rateError) {
    console.error("Email payment action rate limit failed:", rateError.code);
    return page(
      "Payment action unavailable",
      "The payment service is temporarily unavailable. Please try again later.",
      "",
      503,
    );
  }
  if (rateAllowed !== true) {
    return page(
      "Payment action unavailable",
      "Too many attempts. Please wait and try again.",
      "",
      429,
    );
  }

  let formData: FormData | null = null;
  let requestBody: Record<string, unknown> | null = null;
  if (request.method === "POST") {
    if (isJsonPost) {
      try {
        const body: unknown = await request.json();
        requestBody = body && typeof body === "object"
          ? body as Record<string, unknown>
          : null;
      } catch {
        return jsonResponse(request, { error: "invalid_request" }, 400);
      }
    } else {
      try {
        formData = await request.formData();
      } catch {
        return invalidPage();
      }
    }
  }
  const token = requestToken(
    request,
    isJsonPost
      ? typeof requestBody?.token === "string" ? requestBody.token : ""
      : formData?.get("token")?.toString(),
  );
  if (!token) {
    return isJsonPost
      ? jsonResponse(request, { error: "invalid_or_expired_action" }, 400)
      : invalidPage();
  }
  const hash = await hashPaymentEmailToken(token);
  const { data: tokenRateAllowed, error: tokenRateError } = await client.rpc(
    "consume_payment_email_action_rate_limit",
    {
      p_rate_key: await tokenRateLimitKey(hash),
      p_limit: 20,
      p_window_seconds: 600,
    },
  );
  if (tokenRateError) {
    console.error(
      "Email payment token rate limit failed:",
      tokenRateError.code,
    );
    return isJsonPost
      ? jsonResponse(request, { error: "service_unavailable" }, 503)
      : page(
        "Payment action unavailable",
        "The payment service is temporarily unavailable. Please try again later.",
        "",
        503,
      );
  }
  if (tokenRateAllowed !== true) {
    return isJsonPost
      ? jsonResponse(request, { error: "rate_limited" }, 429)
      : page(
        "Payment action unavailable",
        "Too many attempts for this payment link. Please wait and try again.",
        "",
        429,
      );
  }
  const { data: actionToken, error: tokenError } = await client
    .from("payment_email_action_tokens")
    .select(
      "payment_request_id, action, reviewer_email, expires_at, consumed_at, revoked_at",
    )
    .eq("token_hash", hash)
    .maybeSingle();
  if (tokenError) {
    console.error("Email payment action lookup failed:", tokenError.code);
    if (isJsonPost) {
      return jsonResponse(request, { error: "service_unavailable" }, 503);
    }
    return page(
      "Payment action unavailable",
      "The payment service is temporarily unavailable. Please try again later.",
    );
  }
  if (
    !actionToken ||
    actionToken.reviewer_email !== reviewerEmail ||
    !isPaymentEmailActionTokenActive(actionToken)
  ) {
    return isJsonPost
      ? jsonResponse(request, { error: "invalid_or_expired_action" }, 400)
      : invalidPage();
  }

  const isPreviewPost = isJsonPost && requestBody?.intent === "preview";
  if (request.method === "GET" || isPreviewPost) {
    const { data: payment, error } = await client
      .from("premium_payment_requests")
      .select(
        "id, amount_centavos, currency, merchant_transaction_reference, payment_date, payment_time, payment_status, customer_full_name, payment_plans(name)",
      )
      .eq("id", actionToken.payment_request_id)
      .maybeSingle();
    if (error || !payment || payment.payment_status !== "under_review") {
      return isJsonPost
        ? jsonResponse(request, { error: "invalid_or_expired_action" }, 400)
        : invalidPage();
    }
    const plan = payment.payment_plans;
    const planName = plan && typeof plan === "object" && "name" in plan
      ? plan.name
      : "Premium";
    if (isJsonPost) {
      return jsonResponse(request, {
        action: actionToken.action,
        customer: payment.customer_full_name,
        plan: planName,
        currency: payment.currency,
        amount_centavos: payment.amount_centavos,
        reference: payment.merchant_transaction_reference,
        payment_date: payment.payment_date,
        payment_time: payment.payment_time,
      });
    }
    const details = `<p>Customer: ${
      escapeHtml(payment.customer_full_name)
    }<br>Plan: ${escapeHtml(planName)}<br>Amount: ${
      escapeHtml(payment.currency)
    } ${(payment.amount_centavos / 100).toFixed(2)}<br>Reference: ${
      escapeHtml(payment.merchant_transaction_reference)
    }<br>Entered payment date/time: ${escapeHtml(payment.payment_date)} ${
      escapeHtml(payment.payment_time)
    }</p>`;
    const isApproval = actionToken.action === "approve";
    const confirmation = isApproval
      ? `<label><input type="checkbox" name="confirm_received" value="true" required> I verified that this exact transaction was received in the official GCash account.</label><button type="submit">Confirm payment approval</button>`
      : `<label for="reason">Reason for rejection</label><textarea id="reason" name="rejection_reason" maxlength="1000" required></textarea><button type="submit">Confirm payment rejection</button>`;
    const form =
      `<form method="post" action="/functions/v1/payment-email-action"><input type="hidden" name="token" value="${
        escapeHtml(token)
      }">${details}${confirmation}</form><p><small>Opening this page does not change payment status. The action is recorded only after you confirm.</small></p>`;
    return page(
      isApproval ? "Verify and approve payment" : "Review and reject payment",
      isApproval
        ? "Compare the entered details with the receipt, then verify the transaction in authorized GCash merchant or provider records. A receipt image alone does not prove that money was received."
        : "Confirm that this payment should be rejected. Premium will remain inactive.",
      form,
    );
  }

  if (isJsonPost && requestBody?.intent !== "confirm") {
    return jsonResponse(request, { error: "invalid_request" }, 400);
  }

  const confirmReceived = isJsonPost
    ? requestBody?.confirm_received === true
    : formData?.get("confirm_received") === "true";
  const rejectionReason = isJsonPost
    ? typeof requestBody?.rejection_reason === "string"
      ? requestBody.rejection_reason
      : ""
    : formData?.get("rejection_reason")?.toString() ?? "";
  const { data: result, error: reviewError } = await client.rpc(
    "review_premium_payment_by_email_token",
    {
      p_token_hash: hash,
      p_decision: actionToken.action,
      p_confirm_received: confirmReceived,
      p_rejection_reason: rejectionReason,
    },
  );
  if (reviewError || !result) {
    if (isJsonPost) {
      return jsonResponse(request, {
        error: "action_not_completed",
      }, 409);
    }
    return page(
      "Payment action not completed",
      "This action could not be completed. The link may have expired or already been used. Refresh the payment email before retrying.",
    );
  }
  const paymentId = result.payment_request_id;
  if (typeof paymentId === "string") {
    const { data: notification } = await client
      .from("payment_email_notifications")
      .select("id")
      .eq("payment_request_id", paymentId)
      .eq("notification_type", "customer_payment_reviewed")
      .maybeSingle();
    if (notification?.id) {
      const delivery = await deliverPaymentNotification(
        client,
        notification.id,
      );
      if (!delivery.delivered) {
        console.error(
          "Customer payment status email remains queued:",
          delivery.errorCode,
        );
      }
    }
  }
  const successMessage = actionToken.action === "approve"
    ? "The verified transaction was approved and Premium activation was recorded."
    : "The payment was rejected. Premium remains inactive.";
  if (isJsonPost) {
    return jsonResponse(request, {
      action: actionToken.action,
      message: successMessage,
    });
  }
  return page(
    actionToken.action === "approve" ? "Payment approved" : "Payment rejected",
    successMessage,
  );
});
