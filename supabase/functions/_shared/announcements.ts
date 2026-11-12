export function isValidAnnouncementSchedule(
  publishedAt: unknown,
  expiresAt: unknown,
): boolean {
  if (
    typeof publishedAt !== "string" ||
    typeof expiresAt !== "string" ||
    !publishedAt.trim() ||
    !expiresAt.trim()
  ) {
    return false;
  }

  const publishedTime = Date.parse(publishedAt);
  const expiryTime = Date.parse(expiresAt);
  return Number.isFinite(publishedTime) &&
    Number.isFinite(expiryTime) &&
    expiryTime > publishedTime;
}
