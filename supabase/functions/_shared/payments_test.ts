import {
  type GcashPaymentPlan,
  missingPaymentServiceVariables,
  normalizePhilippineMobileNumber,
  parseLuminhawAppUrl,
  paymentConfigurationIssues,
  paymentEmailConfigurationIssues,
  paymentEmailMode,
  paymentEmailSender,
  paymentEmailTestRecipient,
  paymentReadinessIssues,
  RESEND_DEVELOPMENT_SENDER,
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
    amount_centavos: 49900,
    currency: "PHP",
    duration_days: 365,
    qr_storage_path: "plans/GCash-MyQR-499.PNG.jpg",
  },
];

function readinessInput(plans = configuredPlans) {
  return {
    configurationIssues: [],
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

  const incorrectYearlyPrice = configuredPlans.map((plan) =>
    plan.code === "premium_365_days"
      ? { ...plan, amount_centavos: 149900 }
      : plan
  );
  if (
    !paymentReadinessIssues(readinessInput(incorrectYearlyPrice)).includes(
      "yearly_plan_configuration_invalid",
    )
  ) {
    throw new Error("The former yearly price must block checkout.");
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
      "resend_email_mode_missing",
      "supabase_url_missing",
    ]
  ) {
    if (!missing.includes(requiredIssue)) {
      throw new Error(`Missing environment readiness issue: ${requiredIssue}`);
    }
  }
});

Deno.test("Resend sender precedence and verified-domain matching are explicit", () => {
  const values: Record<string, string> = {
    RESEND_EMAIL_MODE: "production",
    RESEND_FROM_EMAIL: "Other Name <payments@mail.example.test>",
    PREMIUM_EMAIL_FROM: "Other Name <payments@mail.example.test>",
    RESEND_VERIFIED_DOMAIN: "mail.example.test",
    LUMINHAW_APP_URL: "https://luminhawofficial.github.io/LUMINHAW-APP/",
  };
  const getEnv = (name: string) => values[name];
  if (
    paymentEmailSender(getEnv) !== "LUMINHAW <payments@mail.example.test>" ||
    paymentEmailConfigurationIssues(getEnv).length !== 0
  ) {
    throw new Error("A matching sender on the verified domain should pass.");
  }

  values.PREMIUM_EMAIL_FROM = "other@mail.example.test";
  if (
    paymentEmailSender(getEnv) !== null ||
    !paymentEmailConfigurationIssues(getEnv).includes(
      "resend_sender_configuration_conflict",
    )
  ) {
    throw new Error("Conflicting sender settings must fail closed.");
  }

  values.PREMIUM_EMAIL_FROM = values.RESEND_FROM_EMAIL;
  values.RESEND_VERIFIED_DOMAIN = "unrelated.example.test";
  if (
    paymentEmailSender(getEnv) !== null ||
    !paymentEmailConfigurationIssues(getEnv).includes(
      "resend_sender_domain_mismatch",
    )
  ) {
    throw new Error("A sender outside the verified domain must fail closed.");
  }
});

Deno.test("development email mode forces the Resend sender and account recipient", () => {
  const values: Record<string, string> = {
    RESEND_EMAIL_MODE: "development",
    RESEND_TEST_RECIPIENT: "resend-account@example.test",
    RESEND_FROM_EMAIL: "LUMINHAW <wrong@unverified.example.test>",
    PREMIUM_EMAIL_FROM: "different@example.test",
  };
  const getEnv = (name: string) => values[name];
  if (
    paymentEmailMode(getEnv) !== "development" ||
    paymentEmailSender(getEnv) !== RESEND_DEVELOPMENT_SENDER ||
    paymentEmailTestRecipient(getEnv) !== "resend-account@example.test" ||
    paymentEmailConfigurationIssues(getEnv).length !== 0
  ) {
    throw new Error(
      "Development mode must use only the fixed sender and test recipient.",
    );
  }

  values.RESEND_TEST_RECIPIENT = "not-an-email";
  if (
    paymentEmailTestRecipient(getEnv) !== null ||
    !paymentEmailConfigurationIssues(getEnv).includes(
      "resend_test_recipient_invalid",
    )
  ) {
    throw new Error("Development mode must reject invalid test recipients.");
  }
});

Deno.test("production mode never falls back to the development sender", () => {
  const values: Record<string, string> = {
    RESEND_EMAIL_MODE: "production",
  };
  const getEnv = (name: string) => values[name];
  if (
    paymentEmailMode(getEnv) !== "production" ||
    paymentEmailSender(getEnv) !== null ||
    paymentEmailTestRecipient(getEnv) !== null ||
    !paymentEmailConfigurationIssues(getEnv).includes("resend_sender_missing")
  ) {
    throw new Error(
      "Production mode must fail closed instead of using a dev sender.",
    );
  }
});

Deno.test("missing or invalid email mode fails closed", () => {
  const missingMode = paymentEmailConfigurationIssues(() => undefined);
  const invalidMode = paymentEmailConfigurationIssues((name) =>
    name === "RESEND_EMAIL_MODE" ? "testing" : undefined
  );
  if (
    !missingMode.includes("resend_email_mode_missing") ||
    paymentEmailMode((name) =>
        name === "RESEND_EMAIL_MODE" ? "testing" : undefined
      ) !== null ||
    !invalidMode.includes("resend_email_mode_invalid") ||
    paymentEmailSender((name) =>
        name === "RESEND_EMAIL_MODE" ? "testing" : undefined
      ) !== null
  ) {
    throw new Error("Missing and invalid modes must not select a sender.");
  }
});

Deno.test("LUMINHAW application URL must be an HTTPS URL without query or fragment", () => {
  const appUrl = parseLuminhawAppUrl(
    "https://luminhawofficial.github.io/LUMINHAW-APP",
  );
  if (
    appUrl?.toString() !==
      "https://luminhawofficial.github.io/LUMINHAW-APP/" ||
    parseLuminhawAppUrl("http://luminhawofficial.github.io/LUMINHAW-APP") ||
    parseLuminhawAppUrl(
      "https://luminhawofficial.github.io/LUMINHAW-APP/?redirect=elsewhere",
    )
  ) {
    throw new Error("The app URL must be normalized and same-origin safe.");
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

Deno.test("checkout does not require an OCR provider for manual verification", () => {
  const values: Record<string, string> = {
    GCASH_PAYMENTS_ENABLED: "true",
    GCASH_MERCHANT_NAME: "Approved merchant",
    GCASH_MERCHANT_ACCOUNT: "Approved account",
    GCASH_PAYMENT_INSTRUCTIONS: "Approved instructions",
    RESEND_EMAIL_MODE: "development",
    RESEND_API_KEY: "test-resend-key",
    RESEND_TEST_RECIPIENT: "resend-account@example.test",
    RESEND_FROM_EMAIL: "LUMINHAW <test@example.test>",
    RESEND_VERIFIED_DOMAIN: "example.test",
    LUMINHAW_APP_URL: "https://luminhawofficial.github.io/LUMINHAW-APP/",
    SUPABASE_URL: "http://127.0.0.1:54321",
  };
  const getEnv = (name: string) => values[name];
  if (paymentConfigurationIssues(getEnv).length !== 0) {
    throw new Error("Complete local provider and merchant config should pass.");
  }
  if (
    paymentReadinessIssues({
      configurationIssues: paymentConfigurationIssues(getEnv),
      plans: configuredPlans,
    }).length !== 0
  ) {
    throw new Error(
      "Manual payment checkout must not depend on OCR configuration.",
    );
  }
});
