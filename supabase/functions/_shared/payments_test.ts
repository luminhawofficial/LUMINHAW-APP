import {
  type GcashPaymentPlan,
  missingPaymentServiceVariables,
  normalizePhilippineMobileNumber,
  OCR_SPACE_MANUAL_REVIEW_SUPPORTED,
  paymentConfigurationIssues,
  paymentReadinessIssues,
} from "./payments.ts";

const configuredPlans: GcashPaymentPlan[] = [
  {
    code: "premium_30_days",
    enabled: true,
    amount_centavos: 4900,
    currency: "PHP",
    duration_days: 30,
    qr_storage_path: "plans/GCash-MyQR-49.PNG.jpg",
  },
  {
    code: "premium_365_days",
    enabled: true,
    amount_centavos: 149900,
    currency: "PHP",
    duration_days: 365,
    qr_storage_path: "plans/GCash-MyQR-1499.PNG.jpg",
  },
];

function readinessInput(plans = configuredPlans) {
  return {
    configurationIssues: [],
    receiptValidationConfigured: true,
    receiptValidationManualReviewSupported: true,
    plans,
  };
}

Deno.test("Philippine mobile number formats normalize for checkout", () => {
  for (
    const [input, expected] of [
      ["09171234567", "+639171234567"],
      ["639171234567", "+639171234567"],
      ["+63 917-123-4567", "+639171234567"],
    ]
  ) {
    if (normalizePhilippineMobileNumber(input) !== expected) {
      throw new Error(`Could not normalize valid phone number: ${input}`);
    }
  }
});

Deno.test("invalid Philippine mobile numbers are rejected", () => {
  for (const input of ["123456", "+63281234567", "0917123456"]) {
    if (normalizePhilippineMobileNumber(input) !== null) {
      throw new Error(`Invalid phone number was accepted: ${input}`);
    }
  }
});

Deno.test("payment readiness requires the exact enabled plans and QR mappings", () => {
  if (paymentReadinessIssues(readinessInput()).length !== 0) {
    throw new Error("The confirmed monthly and yearly plans should be ready.");
  }

  const incorrectPrice = configuredPlans.map((plan) =>
    plan.code === "premium_30_days" ? { ...plan, amount_centavos: 49000 } : plan
  );
  const issues = paymentReadinessIssues(readinessInput(incorrectPrice));
  if (!issues.includes("monthly_plan_configuration_invalid")) {
    throw new Error("An incorrect plan price must block checkout.");
  }

  const missingYearly = configuredPlans.filter(
    (plan) => plan.code !== "premium_365_days",
  );
  if (
    !paymentReadinessIssues(readinessInput(missingYearly)).includes(
      "yearly_plan_missing",
    )
  ) {
    throw new Error("A missing required Premium plan must block checkout.");
  }
});

Deno.test("payment readiness reports configuration and QR blockers", () => {
  const issues = paymentReadinessIssues({
    configurationIssues: [
      "gcash_payments_disabled",
      "resend_api_key_missing",
    ],
    receiptValidationConfigured: true,
    receiptValidationManualReviewSupported: true,
    plans: configuredPlans,
    unavailableQrPlanCodes: ["premium_30_days"],
  });
  for (
    const requiredIssue of [
      "gcash_payments_disabled",
      "resend_api_key_missing",
      "monthly_qr_unavailable",
    ]
  ) {
    if (!issues.includes(requiredIssue)) {
      throw new Error(`Missing readiness issue: ${requiredIssue}`);
    }
  }
});

Deno.test("payment environment readiness identifies missing local variables", () => {
  const missing = paymentConfigurationIssues(() => undefined);
  for (
    const requiredIssue of [
      "gcash_payments_disabled",
      "gcash_merchant_name_missing",
      "gcash_merchant_account_missing",
      "gcash_payment_instructions_missing",
      "resend_api_key_missing",
      "resend_sender_missing",
      "supabase_url_missing",
      "receipt_validation_not_configured",
    ]
  ) {
    if (!missing.includes(requiredIssue)) {
      throw new Error(`Missing environment readiness issue: ${requiredIssue}`);
    }
  }
});

Deno.test("payment service environment reports missing names but never values", () => {
  const missing = missingPaymentServiceVariables(() => undefined);
  if (
    missing.join(",") !== "SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY"
  ) {
    throw new Error("Missing Supabase runtime settings must be explicit.");
  }
});

Deno.test("complete checkout configuration supports manual review without fabricated confidence", () => {
  const values: Record<string, string> = {
    GCASH_PAYMENTS_ENABLED: "true",
    GCASH_MERCHANT_NAME: "Approved merchant",
    GCASH_MERCHANT_ACCOUNT: "Approved account",
    GCASH_PAYMENT_INSTRUCTIONS: "Approved instructions",
    OCR_SPACE_API_KEY: "test-ocr-key",
    RESEND_API_KEY: "test-resend-key",
    RESEND_FROM_EMAIL: "LUMINHAW <test@example.test>",
    SUPABASE_URL: "http://127.0.0.1:54321",
  };
  const getEnv = (name: string) => values[name];
  if (paymentConfigurationIssues(getEnv).length !== 0) {
    throw new Error("Complete local provider and merchant config should pass.");
  }
  if (
    !OCR_SPACE_MANUAL_REVIEW_SUPPORTED ||
    paymentReadinessIssues({
        configurationIssues: paymentConfigurationIssues(getEnv),
        receiptValidationConfigured: true,
        receiptValidationManualReviewSupported:
          OCR_SPACE_MANUAL_REVIEW_SUPPORTED,
        plans: configuredPlans,
      }).length !== 0
  ) {
    throw new Error(
      "OCR.space is ready only when the RPC accepts missing confidence for manual review.",
    );
  }
});
