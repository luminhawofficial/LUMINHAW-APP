import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2";
import { authenticatedUserId, enforceRateLimit } from "./auth.ts";
import { jsonResponse } from "./http.ts";

export const PAYMENT_PROOF_BUCKET = "premium-payment-proofs";
export const OCR_SPACE_MANUAL_REVIEW_SUPPORTED = true;

export const REQUIRED_GCASH_PLANS = [
  {
    code: "premium_30_days",
    amount_centavos: 4900,
    currency: "PHP",
    duration_days: 30,
    qr_storage_path: "plans/GCash-MyQR-49.PNG.jpg",
    readinessPrefix: "monthly",
  },
  {
    code: "premium_365_days",
    amount_centavos: 149900,
    currency: "PHP",
    duration_days: 365,
    qr_storage_path: "plans/GCash-MyQR-1499.PNG.jpg",
    readinessPrefix: "yearly",
  },
] as const;

export type GcashPaymentPlan = {
  code: string;
  enabled: boolean;
  amount_centavos: number;
  currency: string;
  duration_days: number;
  qr_storage_path: string | null;
};

export type PaymentReadinessInput = {
  configurationIssues: readonly string[];
  receiptValidationConfigured: boolean;
  receiptValidationManualReviewSupported: boolean;
  plans: readonly GcashPaymentPlan[];
  unavailableQrPlanCodes?: readonly string[];
};

export function isExpectedGcashPlan(
  plan: GcashPaymentPlan,
): boolean {
  const expected = REQUIRED_GCASH_PLANS.find(({ code }) => code === plan.code);
  return expected !== undefined &&
    plan.amount_centavos === expected.amount_centavos &&
    plan.currency === expected.currency &&
    plan.duration_days === expected.duration_days &&
    plan.qr_storage_path === expected.qr_storage_path;
}

export function paymentReadinessIssues(
  input: PaymentReadinessInput,
): string[] {
  const issues = [...input.configurationIssues];
  if (
    input.receiptValidationConfigured &&
    !input.receiptValidationManualReviewSupported
  ) {
    issues.push("receipt_validation_manual_review_unsupported");
  }

  for (const expected of REQUIRED_GCASH_PLANS) {
    const prefix = expected.readinessPrefix;
    const plan = input.plans.find(({ code }) => code === expected.code);
    if (!plan) {
      issues.push(`${prefix}_plan_missing`);
      continue;
    }
    if (!plan.enabled) issues.push(`${prefix}_plan_disabled`);
    if (!isExpectedGcashPlan(plan)) {
      issues.push(`${prefix}_plan_configuration_invalid`);
    }
    if (input.unavailableQrPlanCodes?.includes(expected.code)) {
      issues.push(`${prefix}_qr_unavailable`);
    }
  }

  if (
    input.plans.some(
      (plan) =>
        plan.enabled &&
        !REQUIRED_GCASH_PLANS.some(({ code }) => code === plan.code),
    )
  ) {
    issues.push("unsupported_payment_plan_enabled");
  }
  return issues;
}

export function paymentConfigurationIssues(
  getEnv: (name: string) => string | undefined = (name) => Deno.env.get(name),
): string[] {
  const issues: string[] = [];
  if (getEnv("GCASH_PAYMENTS_ENABLED") !== "true") {
    issues.push("gcash_payments_disabled");
  }
  if (!getEnv("GCASH_MERCHANT_NAME")?.trim()) {
    issues.push("gcash_merchant_name_missing");
  }
  if (!getEnv("GCASH_MERCHANT_ACCOUNT")?.trim()) {
    issues.push("gcash_merchant_account_missing");
  }
  if (!getEnv("GCASH_PAYMENT_INSTRUCTIONS")?.trim()) {
    issues.push("gcash_payment_instructions_missing");
  }
  if (!getEnv("RESEND_API_KEY")?.trim()) {
    issues.push("resend_api_key_missing");
  }
  if (
    !getEnv("RESEND_FROM_EMAIL")?.trim() &&
    !getEnv("PREMIUM_EMAIL_FROM")?.trim()
  ) {
    issues.push("resend_sender_missing");
  }
  if (!getEnv("SUPABASE_URL")?.trim()) {
    issues.push("supabase_url_missing");
  }
  if (!getEnv("OCR_SPACE_API_KEY")?.trim()) {
    issues.push("receipt_validation_not_configured");
  }
  return issues;
}

export function missingPaymentServiceVariables(
  getEnv: (name: string) => string | undefined = (name) => Deno.env.get(name),
): string[] {
  return [
    !getEnv("SUPABASE_URL")?.trim() ? "SUPABASE_URL" : null,
    !getEnv("SUPABASE_SERVICE_ROLE_KEY")?.trim()
      ? "SUPABASE_SERVICE_ROLE_KEY"
      : null,
  ].filter((name): name is string => name !== null);
}

export function paymentServiceClient(): SupabaseClient | Response {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const missing = missingPaymentServiceVariables();
  if (missing.length > 0 || !supabaseUrl || !serviceRoleKey) {
    console.error(
      "Payment service-role environment is missing:",
      missing.join(", "),
    );
    return jsonResponse({
      error: {
        code: "payment_configuration_missing",
        message: `Payment function configuration is missing: ${
          missing.join(", ")
        }.`,
      },
    }, 503);
  }
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export function isResponse(
  value: SupabaseClient | Response,
): value is Response {
  return value instanceof Response;
}

export async function paymentUser(
  request: Request,
  bucket: string,
  limit: number,
  windowSeconds: number,
): Promise<string | Response> {
  const userId = await authenticatedUserId(request);
  if (userId instanceof Response) return userId;
  const limitResponse = await enforceRateLimit(
    userId,
    bucket,
    limit,
    windowSeconds,
  );
  return limitResponse ?? userId;
}

export type GcashConfiguration = {
  merchantName: string;
  recipient: string;
  instructions: string;
};

export function gcashMerchantConfiguration(): GcashConfiguration | null {
  const merchantName = Deno.env.get("GCASH_MERCHANT_NAME")?.trim();
  const recipient = Deno.env.get("GCASH_MERCHANT_ACCOUNT")?.trim();
  const instructions = Deno.env.get("GCASH_PAYMENT_INSTRUCTIONS")?.trim();
  if (!merchantName || !recipient || !instructions) {
    return null;
  }
  return { merchantName, recipient, instructions };
}

export function gcashConfiguration(): GcashConfiguration | null {
  if (Deno.env.get("GCASH_PAYMENTS_ENABLED") !== "true") return null;
  return gcashMerchantConfiguration();
}

export function paymentEmailSender(): string | null {
  const sender = Deno.env.get("PREMIUM_EMAIL_FROM")?.trim() ||
    Deno.env.get("RESEND_FROM_EMAIL")?.trim();
  return sender || null;
}

export function isUuid(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

export function normalizePhilippineMobileNumber(value: string): string | null {
  const compact = value.trim().replace(/[()\s-]/g, "");
  const normalized = compact.startsWith("09")
    ? `+63${compact.slice(1)}`
    : compact.startsWith("639")
    ? `+${compact}`
    : compact;
  return /^\+639\d{9}$/.test(normalized) ? normalized : null;
}
