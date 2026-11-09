import {
  gcashConfiguration,
  isExpectedGcashPlan,
  isResponse,
  OCR_SPACE_MANUAL_REVIEW_SUPPORTED,
  paymentConfigurationIssues,
  paymentReadinessIssues,
  paymentServiceClient,
  paymentUser,
  REQUIRED_GCASH_PLANS,
} from "../_shared/payments.ts";
import { deliverPaymentNotification } from "../_shared/payment-email.ts";
import { corsHeaders, jsonResponse } from "../_shared/http.ts";

Deno.serve(async (request: Request): Promise<Response> => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: { code: "method_not_allowed" } }, 405);
  }
  const userId = await paymentUser(
    request,
    "get-premium-payment-status",
    60,
    3600,
  );
  if (userId instanceof Response) return userId;
  const client = paymentServiceClient();
  if (isResponse(client)) return client;

  const paymentsPromise = client
    .from("premium_payment_requests")
    .select(
      "id, plan_id, payment_method, amount_centavos, currency, unique_payment_reference, merchant_transaction_reference, payment_date, payment_status, review_notes, created_at, reviewed_at, entitlement_expires_at, payment_plans(code, name, duration_days)",
    )
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(30);
  const plansPromise = client
    .from("payment_plans")
    .select(
      "code, name, description, amount_centavos, currency, duration_days, enabled, qr_storage_path",
    )
    .order("duration_days");
  const entitlementPromise = client
    .from("subscription_entitlements")
    .select("expires_at")
    .eq("user_id", userId)
    .eq("status", "active")
    .gt("expires_at", new Date().toISOString())
    .order("expires_at", { ascending: false })
    .limit(1);
  const [payments, plans, entitlements] = await Promise.all([
    paymentsPromise,
    plansPromise,
    entitlementPromise,
  ]);
  if (
    payments.error || plans.error || entitlements.error
  ) {
    console.error(
      "Premium payment status query failed:",
      payments.error?.code ??
        plans.error?.code ??
        entitlements.error?.code,
    );
    return jsonResponse({
      error: {
        code: "payment_status_unavailable",
        message:
          "Payment records or plans could not be read. Check the Supabase database and required payment migrations.",
      },
    }, 503);
  }

  const paymentIds = (payments.data ?? []).map((payment) => payment.id);
  if (paymentIds.length > 0) {
    const { data: queuedNotifications, error: queuedError } = await client
      .from("payment_email_notifications")
      .select("id")
      .in("payment_request_id", paymentIds)
      .in("delivery_status", ["pending", "failed", "sending"]);
    if (queuedError) {
      console.error("Payment email retry lookup failed:", queuedError.code);
    } else {
      await Promise.all(
        (queuedNotifications ?? []).map((notification) =>
          deliverPaymentNotification(client, notification.id)
        ),
      );
    }
  }

  const paymentInstructions = gcashConfiguration();
  const unavailableQrPlanCodes: string[] = [];
  const plansWithQr = await Promise.all(
    REQUIRED_GCASH_PLANS.map(async (expectedPlan) => {
      const plan = (plans.data ?? []).find(
        ({ code }) => code === expectedPlan.code,
      );
      if (!plan || !plan.enabled || !isExpectedGcashPlan(plan)) return null;
      const { data, error } = await client.storage
        .from("gcash-payment-assets")
        .createSignedUrl(expectedPlan.qr_storage_path, 300);
      if (error || !data?.signedUrl) {
        console.error(
          "GCash plan QR is unavailable:",
          expectedPlan.code,
          error?.name ?? "signed_url_missing",
        );
        unavailableQrPlanCodes.push(expectedPlan.code);
        return null;
      }
      return { ...plan, qrImageUrl: data.signedUrl };
    }),
  );
  type ReadyPlan = NonNullable<(typeof plansWithQr)[number]>;
  const readyPlans = plansWithQr.filter(
    (plan): plan is ReadyPlan => plan !== null,
  );
  const readinessIssues = paymentReadinessIssues({
    configurationIssues: paymentConfigurationIssues(),
    receiptValidationConfigured: Boolean(
      Deno.env.get("OCR_SPACE_API_KEY")?.trim(),
    ),
    receiptValidationManualReviewSupported:
      OCR_SPACE_MANUAL_REVIEW_SUPPORTED,
    plans: plans.data ?? [],
    unavailableQrPlanCodes,
  });
  const enabled = readinessIssues.length === 0 &&
    readyPlans.length === REQUIRED_GCASH_PLANS.length;
  let paymentMethod = null;
  if (enabled && paymentInstructions) {
    paymentMethod = {
      method: "manual_gcash",
      merchantName: paymentInstructions.merchantName,
      recipient: paymentInstructions.recipient,
      steps: paymentInstructions.instructions,
    };
  }
  return jsonResponse({
    userId,
    enabled,
    readinessIssues,
    paymentMethod,
    plans: enabled ? readyPlans : [],
    payments: payments.data ?? [],
    entitlement: entitlements.data?.[0] ?? null,
  });
});
