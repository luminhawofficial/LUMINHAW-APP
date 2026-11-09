import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'Notifications',
      subtitle: 'Keep up with your plant-care reminders.',
      back: true,
      child: Column(
        children: [
          const AppCard(
            child: Column(
              children: [
                Icon(
                  Icons.notifications_none,
                  color: AppColors.green,
                  size: 40,
                ),
                SizedBox(height: 10),
                Text(
                  "You're all caught up",
                  style: TextStyle(
                    color: AppColors.green,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Plant-care push notifications are not available yet. '
                  'You can manage your reminder preference in Settings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted, height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          PrimaryButton(
            label: 'Notification settings',
            icon: Icons.settings_outlined,
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
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
      if (mounted) {
        setState(
          () => _careReminders =
              preferences.getBool('care_reminders_enabled') ?? false,
        );
      }
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
                  'The preference is stored on this device. Reminder notifications are not configured.',
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
    try {
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setBool('care_reminders_enabled', value);
      if (!saved) {
        throw StateError('The care reminder preference could not be saved.');
      }
      if (mounted) {
        setState(() => _careReminders = value);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save care reminder preference: $error'),
          ),
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
