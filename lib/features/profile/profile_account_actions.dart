import 'package:flutter/material.dart';
import 'package:luminhaw/core/services/ai_conversation_service.dart';
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:luminhaw/core/services/saved_plant_details_store.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';

Future<void> confirmAndDeleteAccount(BuildContext context) async {
  final userId = SupabaseAuthService.currentUser?.id;
  if (userId == null) return;
  final requiresPassword =
      !SupabaseAuthService.hasGoogleProvider ||
      SupabaseAuthService.hasEmailPasswordProvider;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete your account?'),
      content: Text(
        'This permanently deletes your account and associated cloud data. '
        'This account’s locally stored saved Library plant details and care-task data will also be removed. '
        'Device-only records created while signed out remain on this device.'
        '${requiresPassword ? '' : ' For Google accounts, sign in again shortly before deleting.'}',
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

  String? password;
  if (requiresPassword) {
    password = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountReauthenticationDialog(),
    );
    if (!context.mounted || password == null || password.isEmpty) return;
  }

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
    await LocalPlantDataStore.instance.clearPersonalData(ownerId: userId);
  } catch (error) {
    localDataErrors.add(error.toString());
  }
  try {
    await SavedPlantDetailsStore.instance.clearPersonalData(ownerId: userId);
  } catch (error) {
    localDataErrors.add(error.toString());
  }
  try {
    await AiConversationService.clearPersonalData(ownerId: userId);
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
