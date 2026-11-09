const actionTokenLifetimeMilliseconds = 48 * 60 * 60 * 1000;

export function createPaymentEmailToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

export async function hashPaymentEmailToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(token),
  );
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

export function isPaymentEmailToken(value: string): boolean {
  return /^[A-Za-z0-9_-]{43}$/.test(value);
}

export function isPaymentEmailActionTokenActive(
  token: {
    expires_at: string;
    consumed_at: string | null;
    revoked_at: string | null;
  },
  now: number = Date.now(),
): boolean {
  const expiresAt = Date.parse(token.expires_at);
  return Number.isFinite(expiresAt) &&
    expiresAt > now &&
    token.consumed_at === null &&
    token.revoked_at === null;
}

export async function createPaymentEmailActionTokenSet(
  now: number = Date.now(),
): Promise<{
  approveToken: string;
  rejectToken: string;
  approveHash: string;
  rejectHash: string;
  expiresAt: string;
}> {
  const approveToken = createPaymentEmailToken();
  const rejectToken = createPaymentEmailToken();
  const [approveHash, rejectHash] = await Promise.all([
    hashPaymentEmailToken(approveToken),
    hashPaymentEmailToken(rejectToken),
  ]);
  return {
    approveToken,
    rejectToken,
    approveHash,
    rejectHash,
    expiresAt: new Date(now + actionTokenLifetimeMilliseconds).toISOString(),
  };
}

export function paymentEmailTokenReplacementArgs(
  notificationId: string,
  claimToken: string,
  tokenSet: Awaited<ReturnType<typeof createPaymentEmailActionTokenSet>>,
): Record<string, unknown> {
  return {
    p_notification_id: notificationId,
    p_claim_token: claimToken,
    p_approve_token_hash: tokenSet.approveHash,
    p_reject_token_hash: tokenSet.rejectHash,
    p_expires_at: tokenSet.expiresAt,
  };
}
