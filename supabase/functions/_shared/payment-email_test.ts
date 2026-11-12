import {
  customerPaymentAccessMessage,
  paymentEmailHtmlDocument,
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
