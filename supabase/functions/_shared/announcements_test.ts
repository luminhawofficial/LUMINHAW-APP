import { isValidAnnouncementSchedule } from "./announcements.ts";

Deno.test("announcement schedule accepts an expiry after its start", () => {
  if (
    !isValidAnnouncementSchedule(
      "2026-11-12T10:00:00.000Z",
      "2026-11-13T10:00:00.000Z",
    )
  ) {
    throw new Error("A valid announcement schedule should be accepted.");
  }
});

Deno.test("announcement schedule requires both dates and a later expiry", () => {
  const invalidSchedules: [unknown, unknown][] = [
    ["2026-11-12T10:00:00.000Z", null],
    [null, "2026-11-13T10:00:00.000Z"],
    ["not-a-date", "2026-11-13T10:00:00.000Z"],
    ["2026-11-13T10:00:00.000Z", "2026-11-12T10:00:00.000Z"],
    ["2026-11-12T10:00:00.000Z", "2026-11-12T10:00:00.000Z"],
  ];

  if (
    invalidSchedules.some(([publishedAt, expiresAt]) =>
      isValidAnnouncementSchedule(publishedAt, expiresAt)
    )
  ) {
    throw new Error("Incomplete or reversed announcement schedules must fail.");
  }
});
