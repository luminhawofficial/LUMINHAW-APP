import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  createPaymentEmailActionTokenSet,
  paymentEmailTokenReplacementArgs,
} from "./payment-email-token.ts";
import { paymentEmailSender } from "./payments.ts";

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

export function paymentEmailHtmlDocument(content: string): string {
  return `<!doctype html><html lang="en"><head><meta charset="UTF-8"></head><body>${content}</body></html>`;
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

function actionUrl(token: string): string {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  if (!supabaseUrl) throw new Error("email_configuration_missing");
  const url = new URL("/functions/v1/payment-email-action", supabaseUrl);
  if (url.protocol !== "https:") throw new Error("email_configuration_missing");
  url.searchParams.set("token", token);
  return url.toString();
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
  if (!shouldAttemptPaymentNotification(notification.delivery_status)) {
    return { delivered: false, errorCode: "invalid_notification_status" };
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
      "id, proof_storage_path, customer_full_name, customer_mobile_number, customer_email, user_id, amount_centavos, currency, merchant_transaction_reference, payment_date, payment_time, payment_status, review_notes, ocr_reference_number, ocr_transaction_date, ocr_transaction_time, ocr_amount_centavos, ocr_recipient, ocr_transaction_status, ocr_status, rejection_reason, created_at, entitlement_expires_at, payment_plans(name)",
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

  const apiKey = Deno.env.get("RESEND_API_KEY");
  const sender = paymentEmailSender();
  if (!apiKey || !sender) {
    return updateDelivery(
      client,
      notificationId,
      "failed",
      "email_not_configured",
      attemptCount,
      claimToken,
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
    const signedProof = await client.storage
      .from(proofBucket)
      .createSignedUrl(payment.proof_storage_path, 3600);
    if (signedProof.error) {
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
    proofUrl = signedProof.data.signedUrl;
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
    ocrReference: escapeHtml(payment.ocr_reference_number),
    date: escapeHtml(payment.payment_date),
    time: escapeHtml(payment.payment_time),
    ocrDate: escapeHtml(payment.ocr_transaction_date),
    ocrTime: escapeHtml(payment.ocr_transaction_time),
    ocrRecipient: escapeHtml(payment.ocr_recipient ?? "Not detected"),
    submittedAt: escapeHtml(new Date(payment.created_at).toISOString()),
    ocr: escapeHtml(
      payment.ocr_status === "matched"
        ? `Matched reference, amount, date, and time; receipt status ${payment.ocr_transaction_status}.`
        : `Manual review required. One or more receipt fields differ or could not be matched. OCR recipient: ${
          payment.ocr_recipient ?? "not detected"
        }.`,
    ),
    proofUrl: escapeHtml(proofUrl),
    approveUrl: escapeHtml(actionLinks?.approveUrl),
    rejectUrl: escapeHtml(actionLinks?.rejectUrl),
    paymentId: escapeHtml(payment.id),
  };
  const subject = isReviewNotification
    ? "LUMINHAW — New GCash Payment for Verification"
    : `LUMINHAW Premium payment ${payment.payment_status}`;
  const htmlContent = isReviewNotification
    ? `
      <h1>LUMINHAW — New GCash Payment for Verification</h1>
      <p>${values.ocr} This does not confirm that money was received. Check the transaction in the official GCash account before approving.</p>
      <h2>Customer</h2>
      <p>Full name: ${values.fullName}<br>Registered email: ${values.email}<br>GCash phone: ${values.mobile}</p>
      <h2>Subscription</h2>
      <p>Plan: ${values.plan}<br>Amount: ${values.amount}</p>
      <h2>Payment</h2>
      <p>Entered reference: ${values.reference}<br>OCR reference: ${values.ocrReference}<br>Entered transaction date/time: ${values.date} ${values.time}<br>OCR transaction date/time: ${values.ocrDate} ${values.ocrTime}<br>OCR recipient: ${values.ocrRecipient}<br>OCR result: ${values.ocr}<br>Submitted: ${values.submittedAt}<br>Payment submission ID: ${values.paymentId}</p>
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
      payment.payment_status === "approved" && payment.entitlement_expires_at
        ? `<p>Premium access is active until ${
          escapeHtml(payment.entitlement_expires_at)
        }.</p>`
        : ""
    }
      <p>Premium access is activated only after an authorized email approval.</p>`;
  const html = paymentEmailHtmlDocument(htmlContent);

  const emailResult = await sendResendEmail({
    apiKey,
    sender,
    recipient: emailRecipient.recipient,
    subject,
    html,
    idempotencyKey: claimToken,
  });
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
  const { error: updateError } = await client
    .from("payment_email_notifications")
    .update({
      delivery_status: "sent",
      attempt_count: attemptCount,
      provider_message_id: emailResult.providerMessageId,
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
