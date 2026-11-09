import {
  gcashConfiguration,
  isExpectedGcashPlan,
  isResponse,
  normalizePhilippineMobileNumber,
  OCR_SPACE_MANUAL_REVIEW_SUPPORTED,
  paymentConfigurationIssues,
  paymentReadinessIssues,
  paymentServiceClient,
  paymentUser,
  REQUIRED_GCASH_PLANS,
} from "../_shared/payments.ts";
import { corsHeaders, jsonResponse, readJsonBody } from "../_shared/http.ts";

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: { code: "method_not_allowed" } }, 405);
  }

  const userId = await paymentUser(request, "create-premium-payment", 5, 3600);
  if (userId instanceof Response) return userId;
  const parsed = await readJsonBody(request, 4096);
  if ("response" in parsed) return parsed.response;

  const planCode = parsed.body.planCode;
  const fullName = parsed.body.fullName;
  const rawMobileNumber = parsed.body.mobileNumber;
  if (
    typeof planCode !== "string" ||
    !/^[a-z0-9_]{2,40}$/.test(planCode)
  ) {
    return jsonResponse({ error: { code: "invalid_payment_plan" } }, 400);
  }
  if (
    typeof fullName !== "string" ||
    fullName.trim().length < 2 ||
    fullName.trim().length > 120 ||
    typeof rawMobileNumber !== "string"
  ) {
    return jsonResponse(
      { error: { code: "invalid_customer_information" } },
      400,
    );
  }
  if (!REQUIRED_GCASH_PLANS.some(({ code }) => code === planCode)) {
    return jsonResponse(
      { error: { code: "payment_plan_unavailable" } },
      409,
    );
  }
  const mobileNumber = normalizePhilippineMobileNumber(rawMobileNumber);
  if (!mobileNumber) {
    return jsonResponse({ error: { code: "invalid_customer_mobile" } }, 400);
  }
  const client = paymentServiceClient();
  if (isResponse(client)) return client;
  const { data: plans, error: planError } = await client
    .from("payment_plans")
    .select(
      "code, enabled, amount_centavos, currency, duration_days, qr_storage_path",
    );
  if (planError) {
    console.error(
      "Payment plan QR configuration is unavailable:",
      planError?.code,
    );
    return jsonResponse(
      { error: { code: "payment_channel_unavailable" } },
      503,
    );
  }

  const planRows = plans ?? [];
  const unavailableQrPlanCodes = (
    await Promise.all(
      REQUIRED_GCASH_PLANS.map(async (expectedPlan) => {
        const plan = planRows.find(({ code }) => code === expectedPlan.code);
        if (!plan || !plan.enabled || !isExpectedGcashPlan(plan)) return null;
        const { data, error } = await client.storage
          .from("gcash-payment-assets")
          .createSignedUrl(expectedPlan.qr_storage_path, 60);
        if (error || !data?.signedUrl) {
          console.error(
            "Payment plan QR object is unavailable:",
            expectedPlan.code,
            error?.name,
          );
          return expectedPlan.code;
        }
        return null;
      }),
    )
  ).filter((code) => code !== null);
  const receiptValidationConfigured = Boolean(
    Deno.env.get("OCR_SPACE_API_KEY")?.trim(),
  );
  const readinessIssues = paymentReadinessIssues({
    configurationIssues: paymentConfigurationIssues(),
    receiptValidationConfigured,
    receiptValidationManualReviewSupported:
      OCR_SPACE_MANUAL_REVIEW_SUPPORTED,
    plans: planRows,
    unavailableQrPlanCodes,
  });
  if (readinessIssues.length > 0) {
    return jsonResponse(
      {
        error: {
          code: "payment_channel_unavailable",
          message: `Checkout is not ready. Missing requirements: ${
            readinessIssues.join(", ")
          }.`,
          readinessIssues,
        },
      },
      503,
    );
  }

  const paymentInstructions = gcashConfiguration();
  if (!paymentInstructions) {
    return jsonResponse(
      { error: { code: "payment_channel_unavailable" } },
      503,
    );
  }
  const { data: authUser, error: authError } = await client.auth.admin
    .getUserById(userId);
  if (
    authError ||
    !authUser.user?.email ||
    !authUser.user.email_confirmed_at
  ) {
    console.error("Payment customer account lookup failed:", authError?.name);
    return jsonResponse(
      { error: { code: "payment_customer_account_unavailable" } },
      503,
    );
  }
  const uniquePaymentReference = `LUM-${crypto.randomUUID()}`;
  const { data, error } = await client.rpc("create_premium_payment_request", {
    p_user_id: userId,
    p_plan_code: planCode,
    p_payment_reference: uniquePaymentReference,
    p_customer_full_name: fullName.trim(),
    p_customer_mobile_number: mobileNumber,
    p_customer_email: authUser.user.email,
  });
  const payment = Array.isArray(data) ? data[0] : data;
  if (error || !payment) {
    console.error("Payment request creation failed:", error?.code ?? "empty");
    const planUnavailable = error?.message?.includes(
      "Payment plan unavailable",
    );
    const requestAlreadyOpen = error?.message?.includes(
      "Payment request already open",
    );
    return jsonResponse(
      {
        error: {
          code: requestAlreadyOpen
            ? "payment_request_already_open"
            : planUnavailable
            ? "payment_plan_unavailable"
            : error?.message?.includes("Invalid payment request")
            ? "invalid_customer_information"
            : "payment_service_unavailable",
        },
      },
      requestAlreadyOpen || planUnavailable ? 409 : 503,
    );
  }

  return jsonResponse({
    payment,
    instructions: {
      method: "manual_gcash",
      merchantName: paymentInstructions.merchantName,
      recipient: paymentInstructions.recipient,
      steps: paymentInstructions.instructions,
    },
  }, 201);
});
