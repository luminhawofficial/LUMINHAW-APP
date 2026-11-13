import {
  isResponse,
  isUuid,
  PAYMENT_PROOF_BUCKET,
  paymentServiceClient,
  paymentUser,
} from "../_shared/payments.ts";
import { deliverPaymentNotification as sendPaymentNotification } from "../_shared/payment-email.ts";
import {
  inspectReceiptImage,
  manilaDateString,
} from "../_shared/manual-receipts.ts";
import { corsHeaders, jsonResponse, readJsonBody } from "../_shared/http.ts";

const notGcashReceiptMessage =
  "Upload a valid JPG or PNG receipt image, up to 5 MB.";

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: { code: "method_not_allowed" } }, 405);
  }

  const userId = await paymentUser(request, "submit-premium-payment", 5, 3600);
  if (userId instanceof Response) return userId;
  const parsed = await readJsonBody(request, 4096);
  if ("response" in parsed) return parsed.response;

  const requestId = parsed.body.requestId;
  const reference = parsed.body.transactionReference;
  const paymentDate = parsed.body.paymentDate;
  const paymentTime = parsed.body.paymentTime;
  const amountCentavos = parsed.body.amountCentavos;
  const proofPath = parsed.body.proofStoragePath;
  const normalizedReference = typeof reference === "string"
    ? reference.replaceAll(" ", "")
    : "";
  if (
    !isUuid(requestId) ||
    typeof reference !== "string" ||
    !/^[0-9 ]+$/.test(reference) ||
    !/^\d{13}$/.test(normalizedReference) ||
    typeof paymentDate !== "string" ||
    !/^\d{4}-\d{2}-\d{2}$/.test(paymentDate) ||
    (paymentTime != null &&
      (typeof paymentTime !== "string" ||
        !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(paymentTime))) ||
    typeof amountCentavos !== "number" ||
    !Number.isInteger(amountCentavos) ||
    amountCentavos <= 0 ||
    typeof proofPath !== "string"
  ) {
    const invalidReference = typeof reference !== "string" ||
      !/^\d{13}$/.test(normalizedReference);
    const invalidAmount = typeof amountCentavos !== "number" ||
      !Number.isInteger(amountCentavos) ||
      amountCentavos <= 0;
    return jsonResponse({
      success: false,
      status: "validation_failed",
      error_code: invalidReference
        ? "reference_invalid"
        : invalidAmount
        ? "wrong_payment_amount"
        : "invalid_payment_submission",
      message: invalidReference
        ? "Your reference number must contain exactly 13 digits in the format 0000 000 000000."
        : invalidAmount
        ? "Enter the exact payment amount shown for your plan."
        : "Check the payment date, time, and uploaded receipt, then try again.",
    }, 400);
  }
  const now = new Date();
  const todayInManila = manilaDateString(now);
  const earliestInManila = new Date(
    Date.parse(`${todayInManila}T00:00:00.000Z`) - 90 * 86_400_000,
  ).toISOString().slice(0, 10);
  const date = new Date(`${paymentDate}T00:00:00.000Z`);
  if (
    Number.isNaN(date.getTime()) ||
    date.toISOString().slice(0, 10) !== paymentDate ||
    paymentDate > todayInManila ||
    paymentDate < earliestInManila
  ) {
    return jsonResponse({
      success: false,
      status: "validation_failed",
      error_code: "invalid_payment_date",
      message: "Enter the actual payment date, no more than 90 days ago.",
    }, 400);
  }
  if (
    !proofPath.startsWith(`${userId}/${requestId}/`) ||
    proofPath.split("/").length !== 3 ||
    proofPath.length > 255
  ) {
    return jsonResponse({
      success: false,
      status: "validation_failed",
      error_code: "receipt_missing",
      message: "Upload your GCash receipt or take a picture of your receipt.",
    }, 400);
  }

  const client = paymentServiceClient();
  if (isResponse(client)) return client;
  const { data: payment, error: paymentError } = await client
    .from("premium_payment_requests")
    .select("id, payment_status, amount_centavos")
    .eq("id", requestId)
    .eq("user_id", userId)
    .maybeSingle();
  if (paymentError || !payment || payment.payment_status !== "pending") {
    return jsonResponse(
      { error: { code: "payment_request_not_submittable" } },
      409,
    );
  }
  if (payment.amount_centavos !== amountCentavos) {
    return jsonResponse({
      success: false,
      status: "validation_failed",
      error_code: "wrong_payment_amount",
      message:
        "The payment amount does not match your selected subscription plan.",
    }, 400);
  }
  const { data: duplicateReference, error: duplicateError } = await client.rpc(
    "payment_reference_exists",
    {
      p_reference: normalizedReference,
      p_payment_request_id: requestId,
    },
  );
  if (duplicateError) {
    console.error(
      "Payment reference availability check failed:",
      duplicateError.code,
    );
    return jsonResponse({
      error: {
        code: "payment_submission_unavailable",
        message:
          "The payment service is temporarily unavailable. Please try again.",
      },
    }, 503);
  }
  if (duplicateReference === true) {
    return jsonResponse({
      success: false,
      status: "validation_failed",
      error_code: "duplicate_reference",
      message:
        "This GCash reference number has already been submitted. Please check your transaction details.",
      checks: { duplicateReference: true },
    }, 409);
  }

  const directory = `${userId}/${requestId}`;
  const fileName = proofPath.split("/").at(-1)!;
  const { data: files, error: listError } = await client.storage
    .from(PAYMENT_PROOF_BUCKET)
    .list(directory, { search: fileName, limit: 10 });
  const proof = files?.find((file) => file.name === fileName);
  if (
    listError ||
    !proof ||
    typeof proof.metadata?.mimetype !== "string" ||
    !["image/jpeg", "image/png"].includes(
      proof.metadata.mimetype,
    ) ||
    typeof proof.metadata?.size !== "number" ||
    proof.metadata.size === 0 ||
    proof.metadata.size > 5 * 1024 * 1024
  ) {
    return jsonResponse({
      success: false,
      status: "validation_failed",
      error_code: "not_a_receipt",
      message: notGcashReceiptMessage,
    }, 422);
  }
  const { data: proofBlob, error: downloadError } = await client.storage
    .from(PAYMENT_PROOF_BUCKET)
    .download(proofPath);
  if (downloadError || !proofBlob) {
    return jsonResponse({
      success: false,
      status: "validation_failed",
      error_code: "not_a_receipt",
      message: notGcashReceiptMessage,
    }, 422);
  }
  const proofBytes = new Uint8Array(await proofBlob.arrayBuffer());
  const inspectedImage = inspectReceiptImage(proofBytes);
  if (
    proofBytes.length !== proof.metadata.size ||
    proofBytes.length > 5 * 1024 * 1024 ||
    !inspectedImage.valid ||
    inspectedImage.mimeType !== proof.metadata.mimetype
  ) {
    return jsonResponse({
      success: false,
      status: "validation_failed",
      error_code: "not_a_receipt",
      message: notGcashReceiptMessage,
    }, 422);
  }

  const { data, error } = await client.rpc("submit_premium_payment", {
    p_user_id: userId,
    p_payment_request_id: requestId,
    p_transaction_reference: normalizedReference,
    p_payment_date: paymentDate,
    p_payment_time: paymentTime ?? null,
    p_amount_centavos: amountCentavos,
    p_proof_storage_path: proofPath,
    p_ocr_result: null,
  });
  if (error) {
    console.error("Payment submission failed:", error.code);
    return jsonResponse(
      {
        error: {
          code: error.message?.includes("duplicate key")
            ? "duplicate_payment_reference"
            : "payment_submission_unavailable",
          message: error.message?.includes("duplicate key")
            ? "This GCash reference number has already been submitted. Please check your transaction details."
            : "The payment could not be submitted. Please try again later.",
        },
      },
      error.message?.includes("duplicate key") ? 409 : 503,
    );
  }
  if (data === "duplicate_reference") {
    return jsonResponse(
      {
        success: false,
        status: "validation_failed",
        error_code: "duplicate_reference",
        message:
          "This GCash reference number has already been submitted. Please check your transaction details.",
        checks: { duplicateReference: true },
      },
      409,
    );
  }
  if (data !== "under_review") {
    return jsonResponse({
      success: false,
      status: "validation_failed",
      error_code: data === "validation_failed"
        ? "invalid_payment_submission"
        : "payment_request_not_submittable",
      message: "The payment could not be submitted for manual review.",
    }, 422);
  }
  const { data: notification, error: notificationError } = await client
    .from("payment_email_notifications")
    .select("id")
    .eq("payment_request_id", requestId)
    .eq("notification_type", "admin_payment_submitted")
    .maybeSingle();
  if (notificationError) {
    console.error(
      "Payment notification lookup failed:",
      notificationError.code,
    );
  }
  const emailResult = notification?.id
    ? await sendPaymentNotification(client, notification.id)
    : { delivered: false, errorCode: "notification_not_queued" };
  return jsonResponse({
    success: true,
    status: "under_review",
    message:
      "Your receipt has been sent for manual verification. Premium remains inactive until an administrator confirms the transaction in authorized GCash records.",
    submitted: true,
    paymentStatus: data,
    emailNotification: emailResult.delivered ? "sent" : "queued_for_retry",
  });
});
