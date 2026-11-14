import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';
import 'package:luminhaw/features/profile/profile_account_actions.dart';
import 'package:luminhaw/features/profile/profile_avatar.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int _avatarRefreshToken = 0;
  late final Future<Map<String, bool>> _adminCapabilities =
      _loadAdminCapabilities();

  Future<Map<String, bool>> _loadAdminCapabilities() async {
    if (!SupabaseBackend.isInitialized ||
        SupabaseAuthService.currentUser == null) {
      return const {};
    }
    try {
      final response = await SupabaseBackend.client.functions.invoke(
        'admin-api',
        body: {'action': 'session'},
      );
      final data = response.data;
      if (response.status < 200 ||
          response.status >= 300 ||
          data is! Map ||
          data['capabilities'] is! Map) {
        return const {};
      }
      final capabilities = data['capabilities'] as Map;
      return {
        'manage_payments': capabilities['manage_payments'] == true,
        'manage_plant_catalog': capabilities['manage_plant_catalog'] == true,
      };
    } catch (_) {
      return const {};
    }
  }

  Future<void> _openProfileEditor(String route) async {
    final saved = await Navigator.pushNamed(context, route);
    if (!mounted || route != '/edit-profile') return;
    setState(() => _avatarRefreshToken++);
    if (saved == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile changes saved.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = SupabaseAuthService.currentUser;
    final displayName = SupabaseAuthService.displayName ?? 'Plant lover';

    return Column(
      children: [
        const AppHeader(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              const Text(
                'Profile',
                style: TextStyle(
                  color: AppColors.green,
                  fontFamily: 'PlayfairDisplay',
                  fontWeight: FontWeight.w700,
                  fontSize: 26,
                ),
              ),
              const SizedBox(height: 14),
              AppCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        ProfileAvatar(
                          radius: 31,
                          refreshToken: _avatarRefreshToken,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  color: AppColors.green,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                user?.email ?? 'Sign in to see your account',
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11,
                                ),
                              ),
                              if (user != null) ...[
                                const SizedBox(height: 5),
                                Text(
                                  user.emailConfirmedAt == null
                                      ? 'Email not verified'
                                      : 'Email verified',
                                  style: TextStyle(
                                    color: user.emailConfirmedAt == null
                                        ? Colors.orange.shade800
                                        : AppColors.green,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  'Joined ${_profileDate(user.createdAt)}',
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  'Location · ${SupabaseAuthService.location ?? 'Not set (optional)'}',
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        key: const ValueKey('profile-edit-button'),
                        onPressed: () => _openProfileEditor(
                          user == null ? '/login' : '/edit-profile',
                        ),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit Profile'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.green,
                          minimumSize: const Size.fromHeight(48),
                          side: const BorderSide(color: AppColors.green),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _ProfileLink(
                icon: Icons.workspace_premium_outlined,
                title: 'Subscription & payment',
                onTap: () => Navigator.pushNamed(context, '/premium'),
              ),
              FutureBuilder<Map<String, bool>>(
                future: _adminCapabilities,
                builder: (context, snapshot) {
                  final capabilities = snapshot.data ?? const {};
                  return Column(
                    children: [
                      if (capabilities['manage_payments'] == true)
                        _ProfileLink(
                          icon: Icons.fact_check_outlined,
                          title: 'GCash payment review',
                          onTap: () =>
                              Navigator.pushNamed(context, '/admin/payments'),
                        ),
                      if (capabilities['manage_plant_catalog'] == true)
                        _ProfileLink(
                          icon: Icons.local_florist_outlined,
                          title: 'Manage plant library',
                          onTap: () =>
                              Navigator.pushNamed(context, '/admin/plants'),
                        ),
                    ],
                  );
                },
              ),
              _ProfileLink(
                icon: Icons.notifications_none,
                title: 'Notifications',
                onTap: () => Navigator.pushNamed(context, '/settings'),
              ),
              _ProfileLink(
                icon: Icons.local_florist_outlined,
                title: 'Saved plants',
                onTap: () =>
                    Navigator.pushNamed(context, '/saved-plant-details'),
              ),
              _ProfileLink(
                icon: Icons.yard_outlined,
                title: 'My Garden',
                onTap: () => Navigator.pushNamed(context, '/garden'),
              ),
              _ProfileLink(
                icon: Icons.history,
                title: 'Plant identification history',
                onTap: () => Navigator.pushNamed(context, '/history'),
              ),
              _ProfileLink(
                icon: Icons.auto_awesome_outlined,
                title: 'AI assistant conversation history',
                onTap: () => Navigator.pushNamed(context, '/ai-history'),
              ),
              _ProfileLink(
                icon: Icons.monitor_heart_outlined,
                title: 'Plant health checker',
                onTap: () => Navigator.pushNamed(context, '/health'),
              ),
              _ProfileLink(
                icon: Icons.show_chart,
                title: 'Growth tracker',
                onTap: () => Navigator.pushNamed(context, '/growth'),
              ),
              _ProfileLink(
                icon: Icons.water_drop_outlined,
                title: 'Plant care history',
                onTap: () => Navigator.pushNamed(context, '/growth'),
              ),
              _ProfileLink(
                icon: Icons.settings_outlined,
                title: 'Settings',
                onTap: () => Navigator.pushNamed(context, '/settings'),
              ),
              _ProfileLink(
                icon: Icons.help_outline,
                title: 'Help / About',
                onTap: () => Navigator.pushNamed(context, '/about'),
              ),
              _ProfileLink(
                icon: Icons.policy_outlined,
                title: 'Privacy Policy / Terms',
                onTap: () => Navigator.pushNamed(context, '/privacy'),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: user == null ? 'Log in' : 'Log out',
                onPressed: user == null
                    ? () => Navigator.pushNamed(context, '/login')
                    : () => _signOut(context),
              ),
              if (user != null) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => confirmAndDeleteAccount(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade800,
                    minimumSize: const Size.fromHeight(48),
                    side: BorderSide(color: Colors.red.shade800),
                  ),
                  child: const Text('Delete account'),
                ),
              ],
              const SizedBox(height: 12),
              if (!SupabaseBackend.isInitialized)
                SetupNotice(message: SupabaseBackend.configurationMessage),
            ],
          ),
        ),
      ],
    );
  }
}

String _profileDate(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return 'Unavailable';
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

Future<bool> confirmLogout(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Log out account?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black87,
                  fontFamily: 'PlayfairDisplay',
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _LogoutDialogButton(
                      label: 'Stay here',
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _LogoutDialogButton(
                      label: 'Yes, log out',
                      onPressed: () => Navigator.pop(context, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ) ??
    false;

Future<void> _signOut(BuildContext context) async {
  if (!await confirmLogout(context) || !context.mounted) return;

  try {
    await SupabaseAuthService.signOut();
    if (context.mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not sign out: $error')));
    }
  }
}

class _LogoutDialogButton extends StatelessWidget {
  const _LogoutDialogButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      backgroundColor: const Color(0xFFE0EFDC),
      foregroundColor: AppColors.green,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
    child: Text(label, textAlign: TextAlign.center),
  );
}

class _ProfileLink extends StatelessWidget {
  const _ProfileLink({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          onTap: onTap,
          leading: Icon(icon, color: AppColors.green),
          title: Text(title, style: const TextStyle(fontSize: 13)),
          trailing: const Icon(Icons.chevron_right),
        ),
      ),
    );
  }
}
