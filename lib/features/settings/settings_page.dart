import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:luminhaw/core/services/plant_care_recommendations.dart';
import 'package:luminhaw/core/services/plant_notification_service.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _store = LocalPlantDataStore.instance;
  List<CareRecommendation> _careReminders = const [];
  List<SystemAnnouncement> _announcements = const [];
  Object? _careError;
  Object? _announcementError;
  bool _isLoading = true;
  bool _careRemindersEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _careError = null;
      _announcementError = null;
    });
    try {
      final preferences = await SharedPreferences.getInstance();
      _careRemindersEnabled =
          preferences.getBool(
            PlantNotificationService.careRemindersPreferenceKey,
          ) ??
          false;
      await _store.load();
      final now = DateTime.now();
      final careReminders =
          [
                for (final plantName in _store.gardenPlantNames.value)
                  ...PlantCareRecommendations.dueForPlant(
                    plantName: plantName,
                    plantDetails:
                        _store.gardenPlantDetails.value[plantName] ?? const {},
                    growthEntries: _store.growthEntries.value,
                    completedTasks: _store.completedCareTasks.value,
                    now: now,
                  ),
              ]
              .where(
                (reminder) =>
                    reminder.title.toLowerCase().contains('soil moisture') ||
                    reminder.title.toLowerCase().contains('fertilizer'),
              )
              .toList()
            ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
      _careReminders = careReminders;
      if (_careRemindersEnabled) {
        await PlantNotificationService.instance.syncCareReminders(
          store: _store,
          enabled: true,
          now: now,
        );
      }
    } catch (error) {
      _careError = error;
    }
    try {
      _announcements = await PlantNotificationService.instance
          .loadAnnouncements();
    } catch (error) {
      _announcementError = error;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'Notifications',
      subtitle: 'Plant care reminders and important LUMINHAW updates.',
      back: true,
      child: _isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: CircularProgressIndicator(color: AppColors.green),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_careError case final error?)
                  SetupNotice(
                    message: 'Plant reminders could not be loaded: $error',
                  )
                else ...[
                  _sectionTitle('Plant care'),
                  if (_careReminders.isEmpty)
                    const AppCard(
                      child: Text(
                        'No watering or fertilizer reminders are due right now.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    )
                  else ...[
                    for (final reminder in _careReminders)
                      _CareReminderCard(
                        reminder: reminder,
                        enabled: _careRemindersEnabled,
                      ),
                  ],
                  if (!_careRemindersEnabled)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Turn on Care reminders in Settings to receive daily local notifications at 9:00 AM.',
                        style: TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ),
                ],
                const SizedBox(height: 20),
                _sectionTitle('System announcements'),
                if (_announcementError case final error?)
                  SetupNotice(
                    message: 'System announcements could not be loaded: $error',
                  )
                else if (_announcements.isEmpty)
                  const AppCard(
                    child: Text(
                      'There are no current announcements.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  )
                else
                  for (final announcement in _announcements)
                    _AnnouncementCard(announcement: announcement),
                const SizedBox(height: 12),
                PrimaryButton(
                  label: 'Refresh notifications',
                  icon: Icons.refresh,
                  onPressed: _loadNotifications,
                ),
                const SizedBox(height: 6),
                PrimaryButton(
                  label: 'Notification settings',
                  icon: Icons.settings_outlined,
                  onPressed: () => Navigator.pushNamed(context, '/settings'),
                ),
              ],
            ),
    );
  }

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        color: AppColors.green,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _CareReminderCard extends StatelessWidget {
  const _CareReminderCard({required this.reminder, required this.enabled});

  final CareRecommendation reminder;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isFertilizer = reminder.title.toLowerCase().contains('fertilizer');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isFertilizer ? Icons.compost_outlined : Icons.water_drop_outlined,
              color: AppColors.green,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${isFertilizer ? 'Fertilizer' : 'Watering'} · ${reminder.plantName}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reminder.guidance,
                    style: const TextStyle(color: AppColors.muted, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    enabled
                        ? 'Notification scheduled for 9:00 AM daily until care is recorded.'
                        : 'Reminder notifications are turned off.',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.announcement});

  final SystemAnnouncement announcement;

  @override
  Widget build(BuildContext context) {
    final category = switch (announcement.category) {
      'maintenance' => 'Maintenance',
      'feature' => 'New feature',
      'account' => 'Account',
      _ => 'App update',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.campaign_outlined, color: AppColors.green),
          title: Text(announcement.title),
          subtitle: Text(
            '$category · ${_announcementDate(announcement.publishedAt)}',
          ),
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(announcement.title),
              content: Text(announcement.body),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _announcementDate(DateTime date) =>
      '${date.toLocal().year}-${date.toLocal().month.toString().padLeft(2, '0')}-'
      '${date.toLocal().day.toString().padLeft(2, '0')}';
}

class _SettingsPageState extends State<SettingsPage> {
  bool _careReminders = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCareReminders();
  }

  Future<void> _loadCareReminders() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final enabled =
          preferences.getBool(
            PlantNotificationService.careRemindersPreferenceKey,
          ) ??
          false;
      if (enabled) {
        await PlantNotificationService.instance.syncCareReminders(
          store: LocalPlantDataStore.instance,
          enabled: true,
        );
      }
      if (mounted) setState(() => _careReminders = enabled);
    } catch (error) {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Could not load care reminder preference: $error',
                ),
              ),
            );
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'Settings',
      subtitle: 'Manage your preferences and account.',
      back: true,
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              SwitchListTile(
                value: _careReminders,
                secondary: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                activeTrackColor: AppColors.green,
                title: const Text('Care reminders'),
                onChanged: _isSaving ? null : _updateCareReminders,
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'Opt in to daily 9:00 AM watering and stage-based fertilizer reminders for plants in My Garden. Reminders use general care guidance and can be turned off here.',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ),
              const Divider(height: 1),
              _SettingsAction(
                title: 'Change password',
                onTap: () => Navigator.pushNamed(context, '/forgot'),
              ),
              _SettingsAction(
                title: 'Privacy and terms',
                onTap: () => Navigator.pushNamed(context, '/privacy'),
              ),
              _SettingsAction(
                title: 'Replay introduction',
                onTap: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('onboarding_complete', false);
                  if (context.mounted) {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/',
                      (_) => false,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateCareReminders(bool value) async {
    setState(() => _isSaving = true);
    var preferenceSaved = false;
    try {
      if (value &&
          !await PlantNotificationService.instance.requestPermission()) {
        throw StateError(
          'Notification permission was not granted. Enable notifications in device settings and try again.',
        );
      }
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setBool(
        PlantNotificationService.careRemindersPreferenceKey,
        value,
      );
      if (!saved) {
        throw StateError('The care reminder preference could not be saved.');
      }
      preferenceSaved = true;
      await PlantNotificationService.instance.syncCareReminders(
        store: LocalPlantDataStore.instance,
        enabled: value,
      );
      if (mounted) {
        setState(() => _careReminders = value);
      }
    } catch (error) {
      var failure = error;
      if (preferenceSaved) {
        try {
          final preferences = await SharedPreferences.getInstance();
          await preferences.setBool(
            PlantNotificationService.careRemindersPreferenceKey,
            _careReminders,
          );
        } catch (rollbackError) {
          failure = StateError(
            '$error Preference rollback also failed: $rollbackError',
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update care reminders: $failure')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: ListTile(
        onTap: onTap,
        title: Text(title),
        trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
      ),
    );
  }
}
