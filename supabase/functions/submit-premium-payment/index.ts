import {
  isResponse,
  isUuid,
  PAYMENT_PROOF_BUCKET,
  paymentServiceClient,
  paymentUser,
} from "../_shared/payments.ts";
import { deliverPaymentNotification as sendPaymentNotification } from "../_shared/payment-email.ts";
import {
  classifyReceipt,
  inspectReceiptImage,
  isSupportedImage,
  readGcashReceipt,
} from "../_shared/receipt-ocr.ts";
import { corsHeaders, jsonResponse, readJsonBody } from "../_shared/http.ts";

const notGcashReceiptMessage =
  "The uploaded image does not appear to be a GCash receipt. Please upload or take a clear picture of your official GCash receipt.";

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
  const proofPath = parsed.body.proofStoragePath;
  const normalizedReference = typeof reference === "string"
    ? reference.replace(/\D/g, "")
    : "";
  if (
    !isUuid(requestId) ||
    typeof reference !== "string" ||
    !/^\d{13}$/.test(normalizedReference) ||
    typeof paymentDate !== "string" ||
    !/^\d{4}-\d{2}-\d{2}$/.test(paymentDate) ||
    typeof paymentTime !== "string" ||
    !/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(paymentTime) ||
    typeof proofPath !== "string"
  ) {
    const invalidReference = typeof reference !== "string" ||
      !/^\d{13}$/.test(normalizedReference);
    return jsonResponse({
      success: false,
      status: "validation_failed",
      error_code: invalidReference
        ? "reference_invalid"
        : "invalid_payment_submission",
      message: invalidReference
        ? "Your reference number must contain exactly 13 digits in the format 0000 000 000000."
        : "Check the payment date, time, and uploaded receipt, then try again.",
    }, 400);
  }
  const date = new Date(`${paymentDate}T00:00:00.000Z`);
  const today = new Date();
  const earliest = new Date(today.getTime() - 90 * 86_400_000);
  earliest.setUTCHours(0, 0, 0, 0);
  today.setUTCHours(0, 0, 0, 0);
  if (
    Number.isNaN(date.getTime()) ||
    date.toISOString().slice(0, 10) !== paymentDate ||
    date > today ||
    date < earliest
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
    .select("id, amount_centavos, payment_status")
    .eq("id", requestId)
    .eq("user_id", userId)
    .maybeSingle();
  if (paymentError || !payment || payment.payment_status !== "pending") {
    return jsonResponse(
      { error: { code: "payment_request_not_submittable" } },
      409,
    );
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
        "This GCash reference number has already been submitted or used.",
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
  const image = inspectReceiptImage(proofBytes);
  if (
    proofBytes.length !== proof.metadata.size ||
    proofBytes.length > 5 * 1024 * 1024 ||
    !isSupportedImage(proofBytes) ||
    proof.metadata.mimetype !== image.mimeType
  ) {
    return jsonResponse({
      success: false,
      status: "validation_failed",
      error_code: "not_a_receipt",
      message: notGcashReceiptMessage,
    }, 422);
  }

  const ocrSpaceKey = Deno.env.get("OCR_SPACE_API_KEY")?.trim();
  if (!ocrSpaceKey) {
    console.error("GCash receipt OCR is not configured.");
    return jsonResponse({
      error: {
        code: "receipt_validation_unavailable",
        message:
          "Receipt validation is temporarily unavailable. Please try again later.",
      },
    }, 503);
  }
  let ocrResult;
  try {
    ocrResult = await readGcashReceipt(proofBytes, ocrSpaceKey);
  } catch (error) {
    console.error(
      "GCash receipt OCR failed:",
      error instanceof Error ? error.message : "unknown",
    );
    return jsonResponse({
      error: {
        code: "receipt_validation_unavailable",
        message:
          "Receipt validation is temporarily unavailable. Please try again later.",
      },
    }, 503);
  }
  const classification = classifyReceipt({
    result: ocrResult,
    submittedReference: normalizedReference,
    submittedDate: paymentDate,
    submittedTime: paymentTime,
    expectedAmountCentavos: payment.amount_centavos,
  });
  if (
    classification.status === "rejected" ||
    classification.status === "inconclusive"
  ) {
    return jsonResponse({
      success: false,
      status: "validation_failed",
      error_code: classification.errorCode ?? "receipt_validation_inconclusive",
      message: classification.reason ??
        "We cannot read the transaction details. Please upload a clearer image.",
      checks: classification.checks,
    }, 422);
  }

  const ocrRecord = {
    referenceNumber: ocrResult.referenceNumber,
    transactionDate: ocrResult.transactionDate,
    transactionTime: ocrResult.transactionTime,
    amountCentavos: ocrResult.amountCentavos,
    recipient: ocrResult.recipient,
    transactionStatus: ocrResult.transactionStatus,
    providerIdentification: ocrResult.providerIdentification,
    hasTransactionMarkers: ocrResult.hasTransactionMarkers,
    confidence: ocrResult.confidence,
    imageWidth: ocrResult.imageWidth,
    imageHeight: ocrResult.imageHeight,
    validImage: classification.checks.validImage,
    isGcashReceipt: classification.checks.isGcashReceipt,
    imageReadable: classification.checks.imageReadable,
    referenceMatch: classification.checks.referenceMatch,
    amountMatch: classification.checks.amountMatch,
    dateMatch: classification.checks.dateMatch,
    timeMatch: classification.checks.timeMatch,
    duplicateReference: classification.checks.duplicateReference,
    status: classification.status,
    reason: classification.reason,
  };
  const { data, error } = await client.rpc("submit_premium_payment", {
    p_user_id: userId,
    p_payment_request_id: requestId,
    p_transaction_reference: normalizedReference,
    p_payment_date: paymentDate,
    p_payment_time: paymentTime,
    p_proof_storage_path: proofPath,
    p_ocr_result: ocrRecord,
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
            ? "This GCash reference number has already been submitted or used."
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
          "This GCash reference number has already been submitted or used.",
        checks: { ...classification.checks, duplicateReference: true },
      },
      409,
    );
  }
  if (data !== "under_review") {
    return jsonResponse({
      success: false,
      status: "validation_failed",
      error_code: data === "validation_failed"
        ? "receipt_validation_inconclusive"
        : "payment_request_not_submittable",
      message:
        "The receipt could not be validated. Please upload a clear GCash receipt and check the transaction details.",
      checks: classification.checks,
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
    message: classification.status === "manual_review"
      ? "Some receipt details differ or could not be matched. Your submission has been sent for manual review; Premium remains inactive."
      : "Your GCash receipt has passed automated checks. Your payment is now waiting for email verification.",
    submitted: true,
    paymentStatus: data,
    ocrStatus: classification.status,
    emailNotification: emailResult.delivered ? "sent" : "queued_for_retry",
  });
});
