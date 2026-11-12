import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:luminhaw/core/services/saved_plant_details_store.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';
import 'package:luminhaw/features/profile/profile_avatar.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int _avatarRefreshToken = 0;

  Future<void> _openProfileEditor(String route) async {
    await Navigator.pushNamed(context, route);
    if (!mounted || route != '/edit-profile') return;
    setState(() => _avatarRefreshToken++);
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
                child: Row(
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
                            style: TextStyle(
                              color: AppColors.green,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            user?.email ?? 'Sign in to see your account',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _openProfileEditor(
                        user == null ? '/login' : '/edit-profile',
                      ),
                      icon: const Icon(Icons.edit_outlined),
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
              _ProfileLink(
                icon: Icons.notifications_none,
                title: 'Notifications',
                onTap: () => Navigator.pushNamed(context, '/settings'),
              ),
              _ProfileLink(
                icon: Icons.history,
                title: 'Scan history',
                onTap: () => Navigator.pushNamed(context, '/history'),
              ),
              _ProfileLink(
                icon: Icons.auto_awesome_outlined,
                title: 'LUMIN AI history',
                onTap: () => Navigator.pushNamed(context, '/ai-history'),
              ),
              _ProfileLink(
                icon: Icons.bookmark_border,
                title: 'Saved plant details',
                onTap: () =>
                    Navigator.pushNamed(context, '/saved-plant-details'),
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
                  onPressed: () => _deleteAccount(context),
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

  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently deletes your account and associated cloud data. '
          'Your garden, growth notes, and saved Library plant details on this device will also be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade800),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;

    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountReauthenticationDialog(),
    );
    if (!context.mounted || password == null || password.isEmpty) return;

    try {
      await SupabaseAuthService.deleteAccount(password: password);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete your account: $error')),
        );
      }
      return;
    }

    final localDataErrors = <String>[];
    try {
      await LocalPlantDataStore.instance.clearPersonalData();
    } catch (error) {
      localDataErrors.add(error.toString());
    }
    try {
      await SavedPlantDetailsStore.instance.clearPersonalData();
    } catch (error) {
      localDataErrors.add(error.toString());
    }
    if (!context.mounted) return;

    Navigator.pushNamedAndRemoveUntil(context, '/welcome', (_) => false);
    if (localDataErrors.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Account deleted, but some local data could not be cleared: '
            '${localDataErrors.join('; ')}',
          ),
        ),
      );
    }
  }
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

class _DeleteAccountReauthenticationDialog extends StatefulWidget {
  const _DeleteAccountReauthenticationDialog();

  @override
  State<_DeleteAccountReauthenticationDialog> createState() =>
      _DeleteAccountReauthenticationDialogState();
}

class _DeleteAccountReauthenticationDialogState
    extends State<_DeleteAccountReauthenticationDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Verify it’s you'),
    content: TextField(
      controller: _password,
      obscureText: true,
      autofocus: true,
      decoration: const InputDecoration(labelText: 'Account password'),
      onChanged: (_) => setState(() {}),
      onSubmitted: (value) {
        if (value.isNotEmpty) Navigator.pop(context, value);
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: _password.text.isEmpty
            ? null
            : () => Navigator.pop(context, _password.text),
        style: TextButton.styleFrom(foregroundColor: Colors.red.shade800),
        child: const Text('Continue'),
      ),
    ],
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
