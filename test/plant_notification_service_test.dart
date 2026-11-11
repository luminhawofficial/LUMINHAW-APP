import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/services/plant_notification_service.dart';

void main() {
  group('PlantNotificationService.nextReminderTime', () {
    test('schedules a due reminder for today at 9 AM when still upcoming', () {
      final next = PlantNotificationService.nextReminderTime(
        DateTime(2026, 11, 10),
        DateTime(2026, 11, 10, 8),
      );

      expect(next, DateTime(2026, 11, 10, 9));
    });

    test('moves a due reminder to tomorrow after 9 AM has passed', () {
      final next = PlantNotificationService.nextReminderTime(
        DateTime(2026, 11, 8),
        DateTime(2026, 11, 10, 9),
      );

      expect(next, DateTime(2026, 11, 11, 9));
    });

    test('keeps a future due date and schedules at 9 AM', () {
      final next = PlantNotificationService.nextReminderTime(
        DateTime(2026, 11, 12, 14),
        DateTime(2026, 11, 10, 10),
      );

      expect(next, DateTime(2026, 11, 12, 9));
    });
  });

  test('parses system announcements and rejects incomplete rows', () {
    final announcement = SystemAnnouncement.fromJson({
      'id': 'announcement-1',
      'title': 'Scheduled maintenance',
      'body': 'The app will be briefly unavailable.',
      'category': 'maintenance',
      'audience': 'all',
      'dismissible': false,
      'published_at': '2026-11-10T00:00:00Z',
    });

    expect(announcement.category, 'maintenance');
    expect(announcement.audience, 'all');
    expect(announcement.dismissible, isFalse);
    expect(announcement.publishedAt, DateTime.utc(2026, 11, 10));
    expect(
      () => SystemAnnouncement.fromJson({'title': 'Incomplete'}),
      throwsFormatException,
    );
  });
}
