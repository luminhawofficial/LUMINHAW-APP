import {
  createPaymentProofSignedUrl,
  customerPaymentAccessMessage,
  customerPremiumAppUrl,
  developmentPaymentEmail,
  paymentActionBridgeUrl,
  paymentEmailHtmlDocument,
  paymentNotificationHoldReason,
  resolvePaymentEmailRecipient,
  sendResendEmail,
  shouldAttemptPaymentNotification,
} from "./payment-email.ts";

Deno.test("admin payment notifications only target the configured reviewer", () => {
  const allowed = resolvePaymentEmailRecipient(
    "admin_payment_submitted",
    " LUMINHAWOFFICIAL@gmail.com ",
    "customer@example.com",
  );
  const denied = resolvePaymentEmailRecipient(
    "admin_payment_submitted",
    "attacker@example.com",
    "customer@example.com",
  );
  if (
    allowed.recipient !== "luminhawofficial@gmail.com" ||
    denied.recipient !== null ||
    denied.errorCode !== "invalid_payment_reviewer_email"
  ) {
    throw new Error("Admin review notifications must be reviewer-only.");
  }
});

Deno.test("customer review notifications only target the stored customer email", () => {
  const allowed = resolvePaymentEmailRecipient(
    "customer_payment_reviewed",
    " CUSTOMER@example.com ",
    "customer@example.com",
  );
  const denied = resolvePaymentEmailRecipient(
    "customer_payment_reviewed",
    "other@example.com",
    "customer@example.com",
  );
  const missing = resolvePaymentEmailRecipient(
    "customer_payment_reviewed",
    "customer@example.com",
    null,
  );
  if (
    allowed.recipient !== "customer@example.com" ||
    denied.recipient !== null ||
    missing.recipient !== null
  ) {
    throw new Error("Customer notifications must use the payment's email.");
  }
});

Deno.test("unknown payment notification types are rejected", () => {
  const result = resolvePaymentEmailRecipient(
    "admin_payment_reminder",
    "luminhawofficial@gmail.com",
    "customer@example.com",
  );
  if (
    result.recipient !== null ||
    result.errorCode !== "invalid_payment_notification_type"
  ) {
    throw new Error("Unexpected payment notification types must fail closed.");
  }
});

Deno.test("sent notifications are not retried; queued notifications are", () => {
  if (
    shouldAttemptPaymentNotification("sent") ||
    shouldAttemptPaymentNotification("pending") !== true ||
    shouldAttemptPaymentNotification("failed") !== true ||
    shouldAttemptPaymentNotification("sending") !== true ||
    shouldAttemptPaymentNotification("unknown") !== false
  ) {
    throw new Error("Email retries must skip sent and unknown states.");
  }
});

Deno.test("payment email HTML declares UTF-8", () => {
  const document = paymentEmailHtmlDocument("<p>Payment reviewed.</p>");
  if (
    !document.includes('<meta charset="UTF-8">') ||
    !document.includes("<p>Payment reviewed.</p>")
  ) {
    throw new Error("Email HTML must declare UTF-8 and preserve its content.");
  }
});

Deno.test("approved payment email confirms Premium activation and provides next steps", () => {
  const message = customerPaymentAccessMessage(
    "approved",
    "2027-11-12T00:00:00Z",
  );
  if (
    !message.includes("your Premium plan is active") ||
    !message.includes("Sign in to LUMINHAW") ||
    !message.includes("No additional purchase is needed") ||
    !message.includes("2027-11-12T00:00:00Z")
  ) {
    throw new Error(
      "Approved payment email must confirm access and explain what to do next.",
    );
  }
});

Deno.test("rejected payment email does not imply Premium was activated", () => {
  const message = customerPaymentAccessMessage("rejected", null);
  if (
    !message.includes("has not been activated") ||
    message.includes("Premium access is active")
  ) {
    throw new Error("Rejected payment email must not claim Premium access.");
  }
});

Deno.test("development email content contains no payment data or action tokens", () => {
  const message = developmentPaymentEmail("customer_payment_reviewed");
  if (
    message.subject !== "LUMINHAW Resend development test" ||
    !message.html.includes("Resend development email test") ||
    !message.html.includes(
      "No payment details or action links are included.",
    ) ||
    message.html.includes("customer@example.com") ||
    message.html.includes("token=")
  ) {
    throw new Error("Development emails must be generic and token-free.");
  }
});

Deno.test("development mode holds customer notices for production", () => {
  if (
    paymentNotificationHoldReason(
        "customer_payment_reviewed",
        "development",
      ) !== "customer_email_held_until_production" ||
    paymentNotificationHoldReason(
        "customer_payment_reviewed",
        "production",
      ) !== null ||
    paymentNotificationHoldReason(
        "admin_payment_submitted",
        "development",
      ) !== null
  ) {
    throw new Error(
      "Development test mail must not consume customer notification records.",
    );
  }
});

Deno.test("customer links use the configured official LUMINHAW app URL", () => {
  const url = customerPremiumAppUrl((name) =>
    name === "LUMINHAW_APP_URL"
      ? "https://luminhawofficial.github.io/LUMINHAW-APP/"
      : undefined
  );
  if (
    url !==
      "https://luminhawofficial.github.io/LUMINHAW-APP/#/premium"
  ) {
    throw new Error("Customer action links must use the official app URL.");
  }
});

Deno.test("review links use the app bridge and keep tokens out of query strings", () => {
  const token = "a".repeat(43);
  const url = new URL(paymentActionBridgeUrl(token, (name) => {
    if (name === "LUMINHAW_APP_URL") {
      return "https://luminhawofficial.github.io/LUMINHAW-APP/";
    }
    if (name === "SUPABASE_URL") return "https://project.supabase.co";
    return undefined;
  }));
  const fragment = new URLSearchParams(url.hash.slice(1));
  if (
    url.origin !== "https://luminhawofficial.github.io" ||
    url.pathname !== "/LUMINHAW-APP/payment-action.html" ||
    url.search ||
    fragment.get("token") !== token ||
    fragment.get("endpoint") !==
      "https://project.supabase.co/functions/v1/payment-email-action"
  ) {
    throw new Error(
      "Review links must use the first-party confirmation bridge.",
    );
  }
});

Deno.test("payment proof emails use expiring signed storage URLs", async () => {
  let actualPath = "";
  let actualExpiry = 0;
  const signedUrl = await createPaymentProofSignedUrl(
    async (path, expiresIn) => {
      actualPath = path;
      actualExpiry = expiresIn;
      return {
        data: {
          signedUrl: "https://storage.example.test/object/sign/private-proof",
        },
        error: null,
      };
    },
    "customer/payment/proof.jpg",
  );
  const unavailable = await createPaymentProofSignedUrl(
    async () => ({
      data: null,
      error: new Error("private object unavailable"),
    }),
    "customer/payment/proof.jpg",
  );
  if (
    actualPath !== "customer/payment/proof.jpg" ||
    actualExpiry !== 3600 ||
    signedUrl !==
      "https://storage.example.test/object/sign/private-proof" ||
    unavailable !== null
  ) {
    throw new Error(
      "Proof image access must remain temporary and fail closed.",
    );
  }
});

Deno.test("Resend email requests carry the expected payload and idempotency key", async () => {
  let callCount = 0;
  const result = await sendResendEmail({
    apiKey: "test-api-key",
    sender: "LUMINHAW <test@example.test>",
    recipient: "reviewer@example.test",
    subject: "Payment review",
    html: "<p>Review locally.</p>",
    idempotencyKey: "test-claim-token",
  }, async (input, init) => {
    callCount++;
    const request = new Request(input, init);
    const body = await request.json();
    if (
      request.url !== "https://api.resend.com/emails" ||
      request.method !== "POST" ||
      !request.headers.get("authorization")?.startsWith("Bearer ") ||
      request.headers.get("idempotency-key") !== "test-claim-token" ||
      body.from !== "LUMINHAW <test@example.test>" ||
      body.to?.[0] !== "reviewer@example.test" ||
      body.subject !== "Payment review" ||
      body.html !== "<p>Review locally.</p>"
    ) {
      throw new Error("The Resend request must include the expected fields.");
    }
    return Response.json({ id: "mock-email-id" });
  });
  if (
    callCount !== 1 ||
    !result.delivered ||
    result.providerMessageId !== "mock-email-id"
  ) {
    throw new Error("The mocked Resend success should be reported as sent.");
  }
});

Deno.test("Resend HTTP, network, timeout, and invalid responses fail explicitly", async () => {
  const rejected = await sendResendEmail({
    apiKey: "test-api-key",
    sender: "test@example.test",
    recipient: "reviewer@example.test",
    subject: "Payment review",
    html: "<p>Review locally.</p>",
    idempotencyKey: "test-claim-token",
  }, async () => new Response("rate limited", { status: 429 }));
  const serverError = await sendResendEmail({
    apiKey: "test-api-key",
    sender: "test@example.test",
    recipient: "reviewer@example.test",
    subject: "Payment review",
    html: "<p>Review locally.</p>",
    idempotencyKey: "test-claim-token",
  }, async () => new Response("provider unavailable", { status: 500 }));
  const unavailable = await sendResendEmail({
    apiKey: "test-api-key",
    sender: "test@example.test",
    recipient: "reviewer@example.test",
    subject: "Payment review",
    html: "<p>Review locally.</p>",
    idempotencyKey: "test-claim-token",
  }, async () => {
    throw new Error("mock network failure");
  });

  const timedOut = await sendResendEmail({
    apiKey: "test-api-key",
    sender: "test@example.test",
    recipient: "reviewer@example.test",
    subject: "Payment review",
    html: "<p>Review locally.</p>",
    idempotencyKey: "test-claim-token",
  }, async () => {
    throw new DOMException("Request timed out", "TimeoutError");
  });
  const invalidResponse = await sendResendEmail({
    apiKey: "test-api-key",
    sender: "test@example.test",
    recipient: "reviewer@example.test",
    subject: "Payment review",
    html: "<p>Review locally.</p>",
    idempotencyKey: "test-claim-token",
  }, async () => Response.json({ accepted: true }));
  if (
    rejected.delivered ||
    rejected.errorCode !== "email_provider_429" ||
    serverError.delivered ||
    serverError.errorCode !== "email_provider_500" ||
    unavailable.delivered ||
    unavailable.errorCode !== "email_provider_unavailable" ||
    timedOut.delivered ||
    timedOut.errorCode !== "email_provider_timeout" ||
    invalidResponse.delivered ||
    invalidResponse.errorCode !== "email_provider_invalid_response"
  ) {
    throw new Error("Mocked Resend failures must remain explicit.");
  }
});

Deno.test("Resend 403 diagnostics are classified without returning provider text", async () => {
  const result = await sendResendEmail({
    apiKey: "test-api-key",
    sender: "test@example.test",
    recipient: "reviewer@example.test",
    subject: "Payment review",
    html: "<p>Review locally.</p>",
    idempotencyKey: "test-claim-token",
  }, async () =>
    Response.json({
      name: "validation_error",
      message: "The sender domain is not verified: private-domain.example",
    }, { status: 403 }));
  if (
    result.delivered ||
    result.errorCode !== "email_provider_403_sender_domain"
  ) {
    throw new Error("403 sender diagnostics must be specific and sanitized.");
  }
});
