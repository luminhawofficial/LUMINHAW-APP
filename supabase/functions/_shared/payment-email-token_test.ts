import {
  createPaymentEmailActionTokenSet,
  createPaymentEmailToken,
  hashPaymentEmailToken,
  isPaymentEmailActionTokenActive,
  isPaymentEmailToken,
  paymentEmailTokenReplacementArgs,
} from "./payment-email-token.ts";

Deno.test("payment email tokens are random, URL-safe bearer secrets", () => {
  const first = createPaymentEmailToken();
  const second = createPaymentEmailToken();
  if (
    !isPaymentEmailToken(first) ||
    !isPaymentEmailToken(second) ||
    first === second
  ) {
    throw new Error("Email action tokens must be independent 256-bit values.");
  }
});

Deno.test("only token hashes fit the database token format", async () => {
  const token = createPaymentEmailToken();
  const hash = await hashPaymentEmailToken(token);
  if (
    !/^[0-9a-f]{64}$/.test(hash) ||
    hash === token ||
    hash !== await hashPaymentEmailToken(token)
  ) {
    throw new Error("The stored token digest must be SHA-256 hex.");
  }
  if (await hashPaymentEmailToken(`${token}x`) === hash) {
    throw new Error("Different tokens must not share a token hash.");
  }
});

Deno.test("approval and rejection token sets are separate and expire in 48 hours", async () => {
  const now = Date.parse("2026-11-07T00:00:00.000Z");
  const tokenSet = await createPaymentEmailActionTokenSet(now);
  if (
    tokenSet.approveToken === tokenSet.rejectToken ||
    tokenSet.approveHash === tokenSet.rejectHash ||
    tokenSet.expiresAt !== "2026-11-09T00:00:00.000Z" ||
    tokenSet.approveHash !==
      await hashPaymentEmailToken(tokenSet.approveToken) ||
    tokenSet.rejectHash !== await hashPaymentEmailToken(tokenSet.rejectToken)
  ) {
    throw new Error(
      "Action tokens must be independent hashed 48-hour secrets.",
    );
  }
});

Deno.test("retry replacement arguments bind hashes to the active delivery claim", async () => {
  const tokenSet = await createPaymentEmailActionTokenSet(0);
  const args = paymentEmailTokenReplacementArgs(
    "notification-id",
    "claim-id",
    tokenSet,
  );
  if (
    args.p_notification_id !== "notification-id" ||
    args.p_claim_token !== "claim-id" ||
    args.p_approve_token_hash !== tokenSet.approveHash ||
    args.p_reject_token_hash !== tokenSet.rejectHash ||
    args.p_approve_token_hash === tokenSet.approveToken ||
    args.p_reject_token_hash === tokenSet.rejectToken
  ) {
    throw new Error("Token replacement must persist hashes under the claim.");
  }
});

Deno.test("expired, consumed, and revoked action tokens cannot be replayed", () => {
  const now = Date.parse("2026-11-07T00:00:00.000Z");
  const activeToken = {
    expires_at: "2026-11-08T00:00:00.000Z",
    consumed_at: null,
    revoked_at: null,
  };
  if (!isPaymentEmailActionTokenActive(activeToken, now)) {
    throw new Error("A fresh, unconsumed token should be active.");
  }
  for (
    const token of [
      { ...activeToken, expires_at: "2026-11-06T00:00:00.000Z" },
      { ...activeToken, consumed_at: "2026-11-06T23:00:00.000Z" },
      { ...activeToken, revoked_at: "2026-11-06T23:00:00.000Z" },
      { ...activeToken, expires_at: "not-a-date" },
    ]
  ) {
    if (isPaymentEmailActionTokenActive(token, now)) {
      throw new Error("Expired or previously used tokens must be inactive.");
    }
  }
});
