import 'dart:async';

import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:luminhaw/core/services/plan_entitlement_store.dart';
import 'package:luminhaw/core/services/plant_care_recommendations.dart';
import 'package:luminhaw/core/services/plant_notification_service.dart';
import 'package:luminhaw/core/services/premium_payment_service.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class _NotificationsPageState extends State<NotificationsPage>
    with WidgetsBindingObserver {
  final _store = LocalPlantDataStore.instance;
  List<CareRecommendation> _careReminders = const [];
  List<SystemAnnouncement> _announcements = const [];
  List<PremiumActivationNotification> _premiumNotifications = const [];
  List<PremiumPaymentRecord> _payments = const [];
  Object? _careError;
  Object? _announcementError;
  Object? _premiumNotificationError;
  Object? _paymentError;
  bool _isLoading = true;
  bool _careRemindersEnabled = false;
  RealtimeChannel? _premiumNotificationChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribeToPremiumNotifications();
    _loadNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final channel = _premiumNotificationChannel;
    if (channel != null) {
      unawaited(_removePremiumNotificationChannel(channel));
    }
    super.dispose();
  }

  void _subscribeToPremiumNotifications() {
    final userId = SupabaseAuthService.currentUser?.id;
    if (userId == null || !SupabaseBackend.isInitialized) return;
    _premiumNotificationChannel = PlantNotificationService.instance
        .watchPremiumNotifications(
          userId: userId,
          onInsert: () => unawaited(_loadPremiumNotifications()),
        );
  }

  Future<void> _removePremiumNotificationChannel(
    RealtimeChannel channel,
  ) async {
    try {
      await SupabaseBackend.client.removeChannel(channel);
    } catch (error) {
      debugPrint('Notification realtime cleanup failed: $error');
    }
  }

  Future<void> _loadPremiumNotifications() async {
    try {
      final notifications = await PlantNotificationService.instance
          .loadPremiumNotifications();
      if (!mounted) return;
      setState(() {
        _premiumNotifications = notifications;
        _premiumNotificationError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _premiumNotificationError = error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _loadNotifications();
    }
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _careError = null;
      _announcementError = null;
      _premiumNotificationError = null;
      _paymentError = null;
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
    try {
      _premiumNotifications = await PlantNotificationService.instance
          .loadPremiumNotifications();
    } catch (error) {
      _premiumNotificationError = error;
    }
    final user = SupabaseAuthService.currentUser;
    if (user == null || user.emailConfirmedAt == null) {
      _payments = const [];
    } else {
      try {
        final options = await PremiumPaymentService.loadOptions();
        _payments = options.payments;
        PlanEntitlementStore.instance.applyVerifiedServerSnapshot(
          userId: options.userId,
          expiresAt: options.premiumExpiresAt,
          productId: options.premiumProductId,
          status: options.premiumStatus,
          startsAt: options.premiumStartsAt,
        );
      } catch (error) {
        _paymentError = error;
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _dismissAnnouncement(SystemAnnouncement announcement) async {
    try {
      await PlantNotificationService.instance.dismissAnnouncement(
        announcement.id,
      );
      if (mounted) {
        setState(() {
          _announcements = _announcements
              .where((item) => item.id != announcement.id)
              .toList(growable: false);
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not dismiss announcement: $error')),
        );
      }
    }
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
                _sectionTitle('Payments and subscription'),
                if (_paymentError case final error?)
                  SetupNotice(
                    message: 'Payment status could not be refreshed: $error',
                  )
                else
                  _PaymentNotices(payments: _payments),
                if (_premiumNotificationError case final error?)
                  SetupNotice(
                    message:
                        'Premium notifications could not be loaded: $error',
                  )
                else
                  for (final notification in _premiumNotifications)
                    _PremiumActivationNotice(notification: notification),
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
                    _AnnouncementCard(
                      announcement: announcement,
                      onDismiss: announcement.dismissible
                          ? () => _dismissAnnouncement(announcement)
                          : null,
                    ),
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

class _PaymentNotices extends StatelessWidget {
  const _PaymentNotices({required this.payments});

  final List<PremiumPaymentRecord> payments;

  @override
  Widget build(BuildContext context) {
    final entitlement = PlanEntitlementStore.instance;
    final expiration = entitlement.expiresAt.value;
    final expiringSoon =
        entitlement.hasPremiumAccess &&
        expiration != null &&
        expiration.difference(DateTime.now().toUtc()).inDays <= 7;
    final hasExpired = entitlement.subscriptionStatus.value == 'Expired';
    final isPremium = entitlement.hasPremiumAccess;
    final notices = payments.take(5).toList(growable: false);
    if (!isPremium && !expiringSoon && !hasExpired && notices.isEmpty) {
      return const AppCard(
        child: Text(
          'No payment or subscription updates.',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }

    return Column(
      children: [
        if (isPremium)
          _PaymentNoticeCard(
            title: 'Premium subscription active',
            detail:
                'Your entitlement is active${entitlement.startsAt.value == null ? '' : ' since ${_announcementDate(entitlement.startsAt.value!)}'}${expiration == null ? '' : ' until ${_announcementDate(expiration)}'}.',
            icon: Icons.verified_outlined,
          ),
        if (expiringSoon)
          _PaymentNoticeCard(
            title: 'Premium subscription expiring soon',
            detail:
                'Your verified Premium entitlement expires ${_announcementDate(expiration)}. Renew before then to keep Premium access.',
            icon: Icons.event_busy_outlined,
          ),
        if (hasExpired && expiration != null)
          _PaymentNoticeCard(
            title: 'Premium subscription expired',
            detail:
                'Premium access ended ${_announcementDate(expiration)}. Your saved plants and garden data remain available.',
            icon: Icons.info_outline,
          ),
        for (final payment in notices)
          _PaymentNoticeCard(
            title: _paymentStatusTitle(payment.status),
            detail:
                '${payment.planName} · ${_announcementDate(payment.createdAt)} · ${_paymentStatusDescription(payment.status)}',
            icon: _paymentStatusIcon(payment.status),
          ),
      ],
    );
  }
}

class _PaymentNoticeCard extends StatelessWidget {
  const _PaymentNoticeCard({
    required this.title,
    required this.detail,
    required this.icon,
  });

  final String title;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(color: AppColors.muted, height: 1.4),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Status retrieved from your account records.',
                  style: TextStyle(color: AppColors.muted, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _PremiumActivationNotice extends StatelessWidget {
  const _PremiumActivationNotice({required this.notification});

  final PremiumActivationNotification notification;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.celebration_outlined, color: AppColors.green),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  notification.title,
                  style: const TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(notification.message),
          const SizedBox(height: 8),
          Text(
            _announcementDate(notification.createdAt),
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

String _paymentStatusTitle(String status) => switch (status) {
  'pending' => 'Payment submitted · Pending',
  'under_review' => 'Payment submitted · Manual review',
  'approved' => 'Payment approved',
  'rejected' => 'Payment rejected',
  'cancelled' => 'Payment cancelled',
  'expired' => 'Payment request expired',
  _ => 'Payment status update',
};

String _paymentStatusDescription(String status) => switch (status) {
  'pending' => 'Waiting for payment review.',
  'under_review' => 'A reviewer is checking the submitted payment.',
  'approved' => 'The payment was approved by the backend.',
  'rejected' => 'The payment was rejected by the reviewer.',
  'cancelled' => 'This payment request was cancelled.',
  'expired' => 'This payment request expired without approval.',
  _ => 'See your subscription page for the latest details.',
};

IconData _paymentStatusIcon(String status) => switch (status) {
  'approved' => Icons.verified_outlined,
  'rejected' || 'expired' => Icons.error_outline,
  _ => Icons.receipt_long_outlined,
};

String _announcementDate(DateTime date) =>
    '${date.toLocal().year}-${date.toLocal().month.toString().padLeft(2, '0')}-'
    '${date.toLocal().day.toString().padLeft(2, '0')}';

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
  const _AnnouncementCard({required this.announcement, this.onDismiss});

  final SystemAnnouncement announcement;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final category = switch (announcement.category) {
      'maintenance' => 'Maintenance',
      'feature' => 'New feature',
      'account' => 'Account',
      'promotion' => 'Premium promotion',
      'plant_care' => 'Plant care',
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
            '$category · ${announcement.audience} audience · '
            '${_announcementDate(announcement.publishedAt)}',
          ),
          trailing: onDismiss == null
              ? null
              : IconButton(
                  tooltip: 'Dismiss announcement',
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close, size: 19),
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
