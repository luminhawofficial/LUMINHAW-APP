import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  createPaymentEmailActionTokenSet,
  paymentEmailTokenReplacementArgs,
} from "./payment-email-token.ts";
import {
  parseLuminhawAppUrl,
  paymentEmailMode,
  paymentEmailSender,
  paymentEmailTestRecipient,
} from "./payments.ts";

const reviewerEmail = "luminhawofficial@gmail.com";
const proofBucket = "premium-payment-proofs";

export function resolvePaymentEmailRecipient(
  notificationType: string,
  notificationRecipient: string,
  customerEmail: string | null,
): { recipient: string; errorCode: null } | {
  recipient: null;
  errorCode: string;
} {
  const normalize = (email: string | null) => email?.trim().toLowerCase() ?? "";
  if (notificationType === "admin_payment_submitted") {
    return normalize(notificationRecipient) === reviewerEmail
      ? { recipient: reviewerEmail, errorCode: null }
      : { recipient: null, errorCode: "invalid_payment_reviewer_email" };
  }
  if (notificationType === "customer_payment_reviewed") {
    if (
      !customerEmail?.trim() ||
      normalize(notificationRecipient) !== normalize(customerEmail)
    ) {
      return { recipient: null, errorCode: "invalid_customer_email_recipient" };
    }
    return { recipient: customerEmail.trim(), errorCode: null };
  }
  return { recipient: null, errorCode: "invalid_payment_notification_type" };
}

export function shouldAttemptPaymentNotification(
  deliveryStatus: string,
): boolean {
  return deliveryStatus === "pending" ||
    deliveryStatus === "failed" ||
    deliveryStatus === "sending";
}

export function paymentNotificationHoldReason(
  notificationType: string,
  mode: string | null,
): string | null {
  return notificationType === "customer_payment_reviewed" &&
      mode === "development"
    ? "customer_email_held_until_production"
    : null;
}

export function paymentEmailHtmlDocument(content: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="UTF-8"></head><body>${content}</body></html>`;
}

export function developmentPaymentEmail(
  notificationType: string,
): { subject: string; html: string } {
  return {
    subject: "LUMINHAW Resend development test",
    html: paymentEmailHtmlDocument(
      `<h1>Resend development email test</h1><p>Delivery check for ${
        escapeHtml(notificationType)
      }.</p><p>No payment details or action links are included.</p>`,
    ),
  };
}

export function customerPaymentAccessMessage(
  paymentStatus: string,
  entitlementExpiresAt: string | null,
): string {
  if (paymentStatus !== "approved") {
    return "<p>Your payment was not approved, so your Premium plan has not been activated.</p>";
  }
  const expiryMessage = entitlementExpiresAt
    ? `<p>Premium access is active until ${
      escapeHtml(entitlementExpiresAt)
    }.</p>`
    : "";
  return `<p>Your payment is approved and your Premium plan is active. Sign in to LUMINHAW to use Premium features. No additional purchase is needed for this payment.</p>${expiryMessage}`;
}

export async function sendResendEmail(
  {
    apiKey,
    sender,
    recipient,
    subject,
    html,
    idempotencyKey,
  }: {
    apiKey: string;
    sender: string;
    recipient: string;
    subject: string;
    html: string;
    idempotencyKey: string;
  },
  fetcher: typeof fetch = fetch,
  timeoutMilliseconds = 15_000,
): Promise<
  { delivered: true; providerMessageId: string | null } | {
    delivered: false;
    errorCode: string;
  }
> {
  let response: Response;
  try {
    response = await fetcher("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
        "Idempotency-Key": idempotencyKey,
      },
      body: JSON.stringify({
        from: sender,
        to: [recipient],
        subject,
        html,
      }),
      signal: AbortSignal.timeout(timeoutMilliseconds),
    });
  } catch (error) {
    return {
      delivered: false,
      errorCode: error instanceof DOMException &&
          (error.name === "TimeoutError" || error.name === "AbortError")
        ? "email_provider_timeout"
        : "email_provider_unavailable",
    };
  }
  if (!response.ok) {
    if (response.status === 403) {
      return {
        delivered: false,
        errorCode: await resendForbiddenErrorCode(response),
      };
    }
    return {
      delivered: false,
      errorCode: `email_provider_${response.status}`,
    };
  }
  let result: { id?: unknown };
  try {
    result = await response.json();
  } catch {
    return { delivered: false, errorCode: "email_provider_invalid_response" };
  }
  if (
    !result || typeof result !== "object" ||
    typeof result.id !== "string" || !result.id.trim()
  ) {
    return { delivered: false, errorCode: "email_provider_invalid_response" };
  }
  return {
    delivered: true,
    providerMessageId: result.id,
  };
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

async function resendForbiddenErrorCode(response: Response): Promise<string> {
  let details: Record<string, unknown> | null = null;
  try {
    const body: unknown = await response.json();
    if (body && typeof body === "object") {
      details = body as Record<string, unknown>;
    }
  } catch {
    return "email_provider_403";
  }
  const providerName = typeof details?.name === "string"
    ? details.name.toLowerCase()
    : typeof details?.code === "string"
    ? details.code.toLowerCase()
    : "";
  const message = typeof details?.message === "string"
    ? details.message.toLowerCase()
    : "";
  if (
    /domain|sender|from/.test(message) &&
    /verif|not allowed|not authorized/.test(message)
  ) {
    return "email_provider_403_sender_domain";
  }
  if (/restricted.*api.?key/.test(providerName)) {
    return "email_provider_403_restricted_api_key";
  }
  if (/invalid.*api.?key/.test(providerName)) {
    return "email_provider_403_invalid_api_key";
  }
  if (/validation_error/.test(providerName)) {
    return "email_provider_403_validation_error";
  }
  return "email_provider_403";
}

export function paymentActionBridgeUrl(
  token: string,
  getEnv: (name: string) => string | undefined = (name) => Deno.env.get(name),
): string {
  const appUrl = parseLuminhawAppUrl(getEnv("LUMINHAW_APP_URL"));
  const supabaseValue = getEnv("SUPABASE_URL");
  if (!appUrl || !supabaseValue) {
    throw new Error("email_configuration_missing");
  }
  let supabaseUrl: URL;
  try {
    supabaseUrl = new URL(supabaseValue);
  } catch {
    throw new Error("email_configuration_missing");
  }
  if (supabaseUrl.protocol !== "https:") {
    throw new Error("email_configuration_missing");
  }
  const endpoint = new URL(
    "/functions/v1/payment-email-action",
    supabaseUrl,
  );
  const bridgeUrl = new URL("payment-action.html", appUrl);
  bridgeUrl.hash = new URLSearchParams({
    token,
    endpoint: endpoint.toString(),
  }).toString();
  return bridgeUrl.toString();
}

export function customerPremiumAppUrl(
  getEnv: (name: string) => string | undefined = (name) => Deno.env.get(name),
): string | null {
  const appUrl = parseLuminhawAppUrl(getEnv("LUMINHAW_APP_URL"));
  if (!appUrl) return null;
  appUrl.hash = "/premium";
  return appUrl.toString();
}

export async function createPaymentProofSignedUrl(
  createSignedUrl: (
    path: string,
    expiresIn: number,
  ) => Promise<{
    data: { signedUrl: string } | null;
    error: unknown | null;
  }>,
  path: string,
): Promise<string | null> {
  const result = await createSignedUrl(path, 3600);
  if (result.error || !result.data?.signedUrl) return null;
  return result.data.signedUrl;
}

function actionUrl(token: string): string {
  const url = paymentActionBridgeUrl(token);
  return url;
}

async function issueEmailActionTokens(
  client: SupabaseClient,
  notificationId: string,
  claimToken: string,
): Promise<{ approveUrl: string; rejectUrl: string }> {
  const tokenSet = await createPaymentEmailActionTokenSet();
  const approveUrl = actionUrl(tokenSet.approveToken);
  const rejectUrl = actionUrl(tokenSet.rejectToken);
  const { error } = await client.rpc(
    "replace_payment_email_action_tokens",
    paymentEmailTokenReplacementArgs(
      notificationId,
      claimToken,
      tokenSet,
    ),
  );
  if (error) {
    console.error("Email action token creation failed:", error.code);
    throw new Error("email_action_token_unavailable");
  }
  return { approveUrl, rejectUrl };
}

export async function deliverPaymentNotification(
  client: SupabaseClient,
  notificationId: string,
): Promise<{ delivered: boolean; errorCode?: string }> {
  const { data: notification, error: notificationError } = await client
    .from("payment_email_notifications")
    .select(
      "id, payment_request_id, notification_type, recipient_email, delivery_status, attempt_count",
    )
    .eq("id", notificationId)
    .maybeSingle();
  if (notificationError || !notification) {
    console.error(
      "Payment email queue lookup failed:",
      notificationError?.code,
    );
    return { delivered: false, errorCode: "notification_not_found" };
  }
  if (notification.delivery_status === "sent") return { delivered: true };
  if (notification.delivery_status === "suppressed") {
    return { delivered: false, errorCode: "notification_suppressed" };
  }
  const mode = paymentEmailMode();
  const holdReason = paymentNotificationHoldReason(
    notification.notification_type,
    mode,
  );
  if (holdReason) {
    console.info("Premium customer email held pending production mode", {
      notificationId,
      notificationType: notification.notification_type,
      mode,
    });
    return { delivered: false, errorCode: holdReason };
  }
  if (!shouldAttemptPaymentNotification(notification.delivery_status)) {
    return { delivered: false, errorCode: "invalid_notification_status" };
  }
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const sender = paymentEmailSender();
  const testRecipient = mode === "development"
    ? paymentEmailTestRecipient()
    : null;
  const premiumAppUrl = mode === "production" ? customerPremiumAppUrl() : null;
  if (!apiKey || !mode || !sender) {
    return { delivered: false, errorCode: "email_not_configured" };
  }
  if (mode === "development" && !testRecipient) {
    return { delivered: false, errorCode: "email_not_configured" };
  }
  if (mode === "production" && !premiumAppUrl) {
    return { delivered: false, errorCode: "email_not_configured" };
  }

  const { data: claimData, error: claimError } = await client.rpc(
    "claim_payment_email_notification",
    { p_notification_id: notificationId },
  );
  const claim = Array.isArray(claimData) ? claimData[0] : claimData;
  if (
    claimError || claim?.claimed !== true ||
    typeof claim?.claim_token !== "string"
  ) {
    if (claimError) {
      console.error("Payment email claim failed:", claimError.code);
    }
    return {
      delivered: false,
      errorCode: claimError
        ? "notification_claim_unavailable"
        : "notification_already_processing",
    };
  }
  const attemptCount = claim.attempt_count as number;
  const claimToken = claim.claim_token as string;

  const { data: payment, error: paymentError } = await client
    .from("premium_payment_requests")
    .select(
      "id, proof_storage_path, customer_full_name, customer_mobile_number, customer_email, user_id, amount_centavos, currency, merchant_transaction_reference, payment_date, payment_time, payment_status, review_notes, rejection_reason, created_at, entitlement_expires_at, payment_plans(name)",
    )
    .eq("id", notification.payment_request_id)
    .maybeSingle();
  if (paymentError || !payment) {
    console.error("Payment email data lookup failed:", paymentError?.code);
    return updateDelivery(
      client,
      notificationId,
      "failed",
      "payment_not_found",
      attemptCount,
      claimToken,
    );
  }

  const emailRecipient = resolvePaymentEmailRecipient(
    notification.notification_type,
    notification.recipient_email,
    payment.customer_email,
  );
  if (emailRecipient.recipient === null) {
    return updateDelivery(
      client,
      notificationId,
      "failed",
      emailRecipient.errorCode,
      attemptCount,
      claimToken,
    );
  }

  const isReviewNotification =
    notification.notification_type === "admin_payment_submitted";
  if (
    (isReviewNotification && payment.payment_status !== "under_review") ||
    (!isReviewNotification &&
      payment.payment_status !== "approved" &&
      payment.payment_status !== "rejected")
  ) {
    return updateDelivery(
      client,
      notificationId,
      "failed",
      "payment_notification_status_mismatch",
      attemptCount,
      claimToken,
    );
  }

  if (mode === "development") {
    if (!testRecipient) {
      return updateDelivery(
        client,
        notificationId,
        "failed",
        "email_not_configured",
        attemptCount,
        claimToken,
      );
    }
    const testEmail = developmentPaymentEmail(
      notification.notification_type,
    );
    const emailResult = await sendResendEmail({
      apiKey,
      sender,
      recipient: testRecipient,
      ...testEmail,
      idempotencyKey: claimToken,
    });
    logEmailDeliveryResult(
      notificationId,
      notification.notification_type,
      mode,
      emailResult,
    );
    if (!emailResult.delivered) {
      return updateDelivery(
        client,
        notificationId,
        "failed",
        emailResult.errorCode,
        attemptCount,
        claimToken,
      );
    }
    return recordDeliveredEmail(
      client,
      notificationId,
      notification.notification_type,
      mode,
      attemptCount,
      claimToken,
      emailResult.providerMessageId,
    );
  }

  let actionLinks: { approveUrl: string; rejectUrl: string } | null = null;
  let proofUrl: string | null = null;
  if (isReviewNotification) {
    if (
      payment.payment_status !== "under_review" || !payment.proof_storage_path
    ) {
      return updateDelivery(
        client,
        notificationId,
        "failed",
        "payment_not_reviewable",
        attemptCount,
        claimToken,
      );
    }
    try {
      actionLinks = await issueEmailActionTokens(
        client,
        notificationId,
        claimToken,
      );
    } catch (error) {
      return updateDelivery(
        client,
        notificationId,
        "failed",
        error instanceof Error
          ? error.message
          : "email_action_token_unavailable",
        attemptCount,
        claimToken,
      );
    }
    proofUrl = await createPaymentProofSignedUrl(
      (path, expiresIn) =>
        client.storage.from(proofBucket).createSignedUrl(path, expiresIn),
      payment.proof_storage_path,
    );
    if (!proofUrl) {
      console.error("Private payment receipt signing failed.");
      return updateDelivery(
        client,
        notificationId,
        "failed",
        "payment_receipt_link_unavailable",
        attemptCount,
        claimToken,
      );
    }
  }

  const plan = payment.payment_plans;
  const planName = plan && typeof plan === "object" && "name" in plan
    ? plan.name
    : "Premium";
  const amount = `${payment.currency} ${
    (payment.amount_centavos / 100).toFixed(2)
  }`;
  const values = {
    fullName: escapeHtml(payment.customer_full_name),
    email: escapeHtml(payment.customer_email),
    mobile: escapeHtml(payment.customer_mobile_number),
    plan: escapeHtml(planName),
    amount: escapeHtml(amount),
    reference: escapeHtml(payment.merchant_transaction_reference),
    date: escapeHtml(payment.payment_date),
    time: escapeHtml(payment.payment_time ?? "Not provided"),
    submittedAt: escapeHtml(new Date(payment.created_at).toISOString()),
    proofUrl: escapeHtml(proofUrl),
    approveUrl: escapeHtml(actionLinks?.approveUrl),
    rejectUrl: escapeHtml(actionLinks?.rejectUrl),
    premiumAppUrl: escapeHtml(premiumAppUrl),
    paymentId: escapeHtml(payment.id),
  };
  const subject = isReviewNotification
    ? "LUMINHAW — New GCash Payment for Verification"
    : `LUMINHAW Premium payment ${payment.payment_status}`;
  const htmlContent = isReviewNotification
    ? `
      <h1>LUMINHAW — New GCash Payment for Verification</h1>
      <p>Compare the manually entered transaction details with the receipt. The screenshot alone does not confirm that money was received. Check authorized GCash merchant or provider records before approving.</p>
      <h2>Customer</h2>
      <p>Full name: ${values.fullName}<br>Registered email: ${values.email}<br>GCash phone: ${values.mobile}</p>
      <h2>Subscription</h2>
      <p>Plan: ${values.plan}<br>Amount: ${values.amount}</p>
      <h2>Payment</h2>
      <p>Entered reference: ${values.reference}<br>Entered transaction date/time: ${values.date} ${values.time}<br>Submitted: ${values.submittedAt}<br>Payment submission ID: ${values.paymentId}</p>
      <p><a href="${values.proofUrl}">View private receipt (link expires in 1 hour)</a></p>
      <p><a href="${values.approveUrl}">Review and approve payment</a></p>
      <p><a href="${values.rejectUrl}">Review and reject payment</a></p>
      <p>These links expire in 48 hours and require a separate confirmation. Do not approve until the actual transaction is verified.</p>`
    : `
      <h1>Your LUMINHAW Premium payment was ${
      escapeHtml(payment.payment_status)
    }.</h1>
      <p>Plan: ${values.plan}<br>Amount: ${values.amount}<br>GCash reference: ${values.reference}<br>Transaction date: ${values.date} ${values.time}</p>
      <p>${
      escapeHtml(
        payment.rejection_reason ?? payment.review_notes ??
          "Your payment was reviewed by LUMINHAW.",
      )
    }</p>
      ${
      customerPaymentAccessMessage(
        payment.payment_status,
        payment.entitlement_expires_at,
      )
    }
      <p><a href="${values.premiumAppUrl}">Open Premium in the LUMINHAW app</a></p>`;
  const html = paymentEmailHtmlDocument(htmlContent);

  const emailResult = await sendResendEmail({
    apiKey,
    sender,
    recipient: emailRecipient.recipient,
    subject,
    html,
    idempotencyKey: claimToken,
  });
  logEmailDeliveryResult(
    notificationId,
    notification.notification_type,
    mode,
    emailResult,
  );
  if (!emailResult.delivered) {
    return updateDelivery(
      client,
      notificationId,
      "failed",
      emailResult.errorCode,
      attemptCount,
      claimToken,
    );
  }
  return recordDeliveredEmail(
    client,
    notificationId,
    notification.notification_type,
    mode,
    attemptCount,
    claimToken,
    emailResult.providerMessageId,
  );
}

function logEmailDeliveryResult(
  notificationId: string,
  notificationType: string,
  mode: string,
  result: { delivered: true; providerMessageId: string | null } | {
    delivered: false;
    errorCode: string;
  },
): void {
  if (result.delivered) {
    console.info("Premium email delivery result", {
      notificationId,
      notificationType,
      mode,
      delivered: true,
    });
  } else {
    console.error("Premium email delivery result", {
      notificationId,
      notificationType,
      mode,
      delivered: false,
      errorCode: result.errorCode,
    });
  }
}

async function recordDeliveredEmail(
  client: SupabaseClient,
  notificationId: string,
  notificationType: string,
  mode: string,
  attemptCount: number,
  claimToken: string,
  providerMessageId: string | null,
): Promise<{ delivered: boolean; errorCode?: string }> {
  const { error: updateError } = await client
    .from("payment_email_notifications")
    .update({
      delivery_status: "sent",
      attempt_count: attemptCount,
      provider_message_id: providerMessageId,
      last_error_code: null,
      delivered_at: new Date().toISOString(),
      delivery_claimed_at: null,
      delivery_claim_token: null,
      updated_at: new Date().toISOString(),
    })
    .eq("id", notificationId)
    .eq("delivery_status", "sending")
    .eq("delivery_claim_token", claimToken);
  if (updateError) {
    console.error(
      "Payment email delivery record update failed:",
      updateError.code,
    );
    return { delivered: false, errorCode: "notification_update_failed" };
  }
  console.info("Premium email delivery recorded", {
    notificationId,
    notificationType,
    mode,
    delivered: true,
  });
  return { delivered: true };
}

async function updateDelivery(
  client: SupabaseClient,
  notificationId: string,
  status: "failed",
  errorCode: string,
  attemptCount: number,
  claimToken: string,
): Promise<{ delivered: false; errorCode: string }> {
  const values: Record<string, unknown> = {
    delivery_status: status,
    delivery_claimed_at: null,
    delivery_claim_token: null,
    last_error_code: errorCode,
    attempt_count: attemptCount,
    updated_at: new Date().toISOString(),
  };
  const { error } = await client
    .from("payment_email_notifications")
    .update(values)
    .eq("id", notificationId)
    .eq("delivery_status", "sending")
    .eq("delivery_claim_token", claimToken);
  if (error) {
    console.error("Payment email failure record update failed:", error.code);
  }
  return { delivered: false, errorCode };
}
