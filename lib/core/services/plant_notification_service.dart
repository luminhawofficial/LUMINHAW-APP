import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:luminhaw/core/services/plant_care_recommendations.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

class SystemAnnouncement {
  const SystemAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.publishedAt,
  });

  final String id;
  final String title;
  final String body;
  final String category;
  final DateTime publishedAt;

  factory SystemAnnouncement.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final body = json['body'];
    final category = json['category'];
    final publishedAt = json['published_at'];
    if (id is! String ||
        title is! String ||
        body is! String ||
        category is! String ||
        publishedAt is! String) {
      throw const FormatException('System announcement data is invalid.');
    }
    return SystemAnnouncement(
      id: id,
      title: title,
      body: body,
      category: category,
      publishedAt: DateTime.parse(publishedAt),
    );
  }
}

class PlantNotificationService {
  PlantNotificationService._();

  static final instance = PlantNotificationService._();
  static const careRemindersPreferenceKey = 'care_reminders_enabled';
  static const _reminderPayloadPrefix = 'care-reminder:';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;

  Future<void> initialize() async {
    final existing = _initialization;
    if (existing != null) return existing;
    final initialization = _initialize();
    _initialization = initialization;
    try {
      await initialization;
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  Future<void> _initialize() async {
    timezone_data.initializeTimeZones();
    final localTimezone = await FlutterTimezone.getLocalTimezone();
    timezone.setLocalLocation(timezone.getLocation(localTimezone.identifier));

    final initialized = await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    if (initialized == false) {
      throw StateError('Local notifications could not be initialized.');
    }
  }

  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    await initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission() ?? false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      final macos = _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >();
      return await macos?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return true;
  }

  Future<void> syncCareReminders({
    required LocalPlantDataStore store,
    required bool enabled,
    DateTime? now,
  }) async {
    await initialize();
    if (!enabled) {
      final pending = await _plugin.pendingNotificationRequests();
      for (final notification in pending) {
        if (notification.payload?.startsWith(_reminderPayloadPrefix) ?? false) {
          await _plugin.cancel(notification.id);
        }
      }
      return;
    }

    await store.load();
    final pending = await _plugin.pendingNotificationRequests();
    for (final notification in pending) {
      if (notification.payload?.startsWith(_reminderPayloadPrefix) ?? false) {
        await _plugin.cancel(notification.id);
      }
    }

    final timestamp = now ?? DateTime.now();
    final reminders = [
      for (final plantName in store.gardenPlantNames.value)
        ...PlantCareRecommendations.dueForPlant(
          plantName: plantName,
          plantDetails: store.gardenPlantDetails.value[plantName] ?? const {},
          growthEntries: store.growthEntries.value,
          completedTasks: store.completedCareTasks.value,
          now: timestamp,
        ),
    ].where(_isNotifiableReminder);

    for (final reminder in reminders) {
      final scheduledAt = nextReminderTime(reminder.dueAt, timestamp);
      await _plugin.zonedSchedule(
        _notificationId(reminder.id),
        _notificationTitle(reminder),
        '${reminder.plantName}: ${reminder.guidance}',
        timezone.TZDateTime.from(scheduledAt, timezone.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'plant_care_reminders',
            'Plant care reminders',
            channelDescription:
                'Watering and fertilizer reminders for saved plants.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: '$_reminderPayloadPrefix${reminder.id}',
      );
    }
  }

  Future<List<SystemAnnouncement>> loadAnnouncements() async {
    if (!SupabaseBackend.isInitialized) {
      throw StateError(SupabaseBackend.configurationMessage);
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await SupabaseBackend.client
        .from('system_announcements')
        .select('id, title, body, category, published_at')
        .eq('is_active', true)
        .lte('published_at', now)
        .or('expires_at.is.null,expires_at.gt.$now')
        .order('published_at', ascending: false)
        .limit(50);
    return rows
        .map(
          (row) => SystemAnnouncement.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  static bool _isNotifiableReminder(CareRecommendation reminder) {
    final title = reminder.title.toLowerCase();
    return title.contains('soil moisture') || title.contains('fertilizer');
  }

  static String _notificationTitle(CareRecommendation reminder) =>
      reminder.title.toLowerCase().contains('fertilizer')
      ? 'Fertilizer reminder'
      : 'Watering reminder';

  static DateTime nextReminderTime(DateTime dueAt, DateTime now) {
    const reminderHour = 9;
    var reminderDate = DateTime(
      dueAt.year,
      dueAt.month,
      dueAt.day,
      reminderHour,
    );
    if (reminderDate.isBefore(DateTime(now.year, now.month, now.day))) {
      reminderDate = DateTime(now.year, now.month, now.day, reminderHour);
    }
    if (!reminderDate.isAfter(now)) {
      reminderDate = DateTime(now.year, now.month, now.day + 1, reminderHour);
    }
    return reminderDate;
  }

  static int _notificationId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}

Future<void> refreshEnabledCareReminders() async {
  final preferences = await SharedPreferences.getInstance();
  if (preferences.getBool(
        PlantNotificationService.careRemindersPreferenceKey,
      ) !=
      true) {
    return;
  }
  await PlantNotificationService.instance.syncCareReminders(
    store: LocalPlantDataStore.instance,
    enabled: true,
  );
}
