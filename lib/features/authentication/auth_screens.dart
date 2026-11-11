import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:luminhaw/core/constants/app_colors.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    if (!SupabaseBackend.isInitialized) {
      _showSetupMessage(context);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final response = await SupabaseAuthService.signIn(
        email: _email.text,
        password: _password.text,
      );
      final user = response.user;
      if (user == null) {
        throw StateError('Supabase did not return an authenticated user.');
      }
      if (user.emailConfirmedAt == null) {
        await SupabaseBackend.client.auth.signOut();
        _showVerificationPage(_email.text.trim());
        return;
      }
      if (response.session == null) {
        throw StateError('Your account does not have an active session.');
      }
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      }
    } on AuthException catch (error) {
      if (_isEmailUnconfirmed(error.message)) {
        _showVerificationPage(_email.text.trim());
        return;
      }
      _showMessage(_sanitizeAuthError(error.message));
    } catch (error) {
      final message = _sanitizeAuthError(error.toString());
      _showMessage(
        message.isEmpty ? 'Could not sign in.' : 'Could not sign in: $message',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showVerificationPage(String email) {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/verification',
      (_) => false,
      arguments: email,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _AuthShell(
      isSignUp: false,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Welcome back.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: AppColors.dark,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your little world of green is waiting.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
            const SizedBox(height: 56),
            _InputField(
              controller: _email,
              label: 'Email address',
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
            ),
            const SizedBox(height: 22),
            _InputField(
              controller: _password,
              label: 'Password',
              obscureText: !_showPassword,
              suffix: IconButton(
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.muted,
                ),
              ),
              validator: (value) =>
                  value == null || value.isEmpty ? 'Enter your password' : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pushNamed(context, '/forgot'),
                style: TextButton.styleFrom(foregroundColor: AppColors.green),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 0),
            PrimaryButton(
              label: _isSubmitting ? 'Signing in…' : 'Log in',
              onPressed: _isSubmitting ? null : _signIn,
            ),
            const SizedBox(height: 20),
            if (!SupabaseBackend.isInitialized)
              SetupNotice(message: SupabaseBackend.configurationMessage),
            const SizedBox(height: 18),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pushNamed(context, '/signup'),
                style: TextButton.styleFrom(foregroundColor: AppColors.green),
                child: const Text.rich(
                  TextSpan(
                    style: TextStyle(color: AppColors.muted),
                    children: [
                      TextSpan(text: 'New to Luminhaw? '),
                      TextSpan(
                        text: 'Create an account',
                        style: TextStyle(color: AppColors.green),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _hasAgreed = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _createAccount() async {
    if (_isSubmitting) return;
    if (!_hasAgreed) {
      _showMessage(
        'Please agree to the Privacy Policy and Terms of Use to continue.',
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    if (!SupabaseBackend.isInitialized) {
      _showSetupMessage(context);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final response = await SupabaseAuthService.signUp(
        name: _name.text,
        email: _email.text,
        password: _password.text,
      );
      final user = response.user;
      if (user == null) {
        throw StateError('Supabase did not return a created account.');
      }
      if (signupResponseIndicatesExistingAccount(user.identities)) {
        _showMessage(
          'An account already uses this email. Try signing in or resetting its password.',
        );
        return;
      }
      if (!mounted) return;

      if (user.emailConfirmedAt == null) {
        if (response.session != null) {
          await SupabaseBackend.client.auth.signOut();
        }
        if (mounted) _showVerificationPage(_email.text.trim());
        return;
      }
      if (response.session == null) {
        throw StateError('Your account does not have an active session.');
      }
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
    } on AuthException catch (error) {
      _showMessage(signUpFailureMessage(error.message));
    } catch (error) {
      final message = _sanitizeAuthError(error.toString());
      _showMessage(
        message.isEmpty
            ? 'Could not create your account. Please try again.'
            : 'Could not create your account: $message',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showVerificationPage(String email) {
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/verification',
      (_) => false,
      arguments: email,
    );
  }

  Future<void> _showPrivacyUsage() => showDialog<void>(
    context: context,
    builder: (_) => const _PrivacyUsageDialog(),
  );

  @override
  Widget build(BuildContext context) {
    return _AuthShell(
      isSignUp: true,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Let's grow together.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: AppColors.dark,
                height: 1.05,
              ),
            ),
            const SizedBox(height: 35),
            _InputField(
              controller: _name,
              label: 'Full name',
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter your name'
                  : null,
            ),
            const SizedBox(height: 16),
            _InputField(
              controller: _email,
              label: 'Email address',
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
            ),
            const SizedBox(height: 16),
            _InputField(
              controller: _password,
              label: 'Password',
              obscureText: true,
              validator: (value) => value == null || value.length < 8
                  ? 'Use at least 8 characters'
                  : null,
            ),
            const SizedBox(height: 16),
            _InputField(
              controller: _confirmPassword,
              label: 'Confirm password',
              obscureText: true,
              validator: (value) =>
                  value != _password.text ? 'Passwords do not match' : null,
            ),
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Checkbox(
                  value: _hasAgreed,
                  onChanged: _isSubmitting
                      ? null
                      : (value) => setState(() => _hasAgreed = value ?? false),
                  activeColor: AppColors.green,
                  checkColor: Colors.white,
                  side: const BorderSide(color: AppColors.green, width: 1.5),
                  visualDensity: const VisualDensity(
                    horizontal: -4,
                    vertical: -4,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Wrap(
                    key: const ValueKey('signup-agreement-links'),
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'I have read and agree to the ',
                        style: TextStyle(
                          color: AppColors.dark,
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                      _AgreementLink(
                        label: 'Privacy Policy',
                        onTap: _showPrivacyUsage,
                      ),
                      const Text(
                        ' and ',
                        style: TextStyle(
                          color: AppColors.dark,
                          fontFamily: 'Poppins',
                          fontSize: 11,
                        ),
                      ),
                      _AgreementLink(
                        label: 'Terms of Use',
                        onTap: _showPrivacyUsage,
                      ),
                      const Text(
                        '.',
                        style: TextStyle(
                          color: AppColors.dark,
                          fontFamily: 'Poppins',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              label: _isSubmitting ? 'Creating account…' : 'Create account',
              onPressed: _isSubmitting ? null : _createAccount,
            ),
            const SizedBox(height: 12),
            if (!SupabaseBackend.isInitialized)
              SetupNotice(message: SupabaseBackend.configurationMessage),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                style: TextButton.styleFrom(foregroundColor: AppColors.green),
                child: const Text.rich(
                  TextSpan(
                    style: TextStyle(color: AppColors.muted),
                    children: [
                      TextSpan(text: 'Already growing with us? '),
                      TextSpan(
                        text: 'Log in',
                        style: TextStyle(color: AppColors.green),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _sanitizeAuthError(String message) {
  final readable = _readableAuthError(message);
  final sanitized = readable
      .replaceAll(RegExp(r'\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b'), '[email]')
      .replaceAll(
        RegExp(
          r'''\b(password|token|secret|api[_-]?key|authorization)\s*[:=]\s*("[^"]*"|'[^']*'|[^\s,;]+)''',
          caseSensitive: false,
        ),
        '[credential redacted]',
      )
      .replaceAll(
        RegExp(
          r'\b(?:sb_(?:publishable|secret)_[A-Za-z0-9_-]+|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)\b',
        ),
        '[credential redacted]',
      )
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .trim();
  if (sanitized.length <= 240) return sanitized;
  return '${sanitized.substring(0, 237)}...';
}

String _readableAuthError(String message) {
  try {
    final decoded = jsonDecode(message);
    if (decoded is Map) {
      final code = decoded['code'];
      final detail = decoded['message'];
      if (code is String && detail is String) return '$code: $detail';
      if (detail is String) return detail;
    }
  } on FormatException {
    // Supabase may return plain text instead of a JSON error payload.
  }
  return message;
}

@visibleForTesting
String signUpFailureMessage(String rawError) {
  final details = _authErrorDetails(rawError);
  final code = details['code']!.toLowerCase();
  final message = details['message']!;
  final normalized = message.toLowerCase();

  if (code.contains('rate_limit') ||
      code.contains('too_many') ||
      normalized.contains('rate limit') ||
      normalized.contains('too many requests')) {
    return 'Email signup is temporarily rate-limited. Wait before trying again.';
  }
  if (code == 'email_exists' ||
      code == 'user_already_exists' ||
      normalized.contains('user already registered') ||
      normalized.contains('email already exists')) {
    return 'An account already uses this email. Try signing in or resetting its password.';
  }
  if (normalized.contains('error sending confirmation email') ||
      normalized.contains('could not send confirmation email') ||
      code == 'confirmation_email_failed') {
    return 'Supabase could not send the confirmation email. Check Supabase Auth email-provider logs, then check Authentication → Users before retrying.';
  }

  final sanitized = _sanitizeAuthError(message);
  return sanitized.isEmpty
      ? 'Account creation failed. Check the Supabase Auth logs and try again.'
      : 'Account creation failed: $sanitized';
}

@visibleForTesting
bool signupResponseIndicatesExistingAccount(List<Object>? identities) =>
    identities != null && identities.isEmpty;

@visibleForTesting
String verificationEmailFailureMessage(String rawError) {
  final details = _authErrorDetails(rawError);
  final normalized = details['message']!.toLowerCase();
  if (details['code']!.toLowerCase().contains('rate_limit') ||
      normalized.contains('rate limit') ||
      normalized.contains('too many requests')) {
    return 'Verification email is temporarily rate-limited. Wait before requesting another.';
  }
  if (normalized.contains('error sending confirmation email') ||
      normalized.contains('could not send confirmation email')) {
    return 'Supabase could not send the verification email. Check Supabase Auth email-provider logs.';
  }
  final message = _sanitizeAuthError(details['message']!);
  return message.isEmpty
      ? 'Could not resend the verification email.'
      : 'Could not resend the verification email: $message';
}

bool _isEmailUnconfirmed(String rawError) {
  final details = _authErrorDetails(rawError);
  final code = details['code']!.toLowerCase();
  final message = details['message']!.toLowerCase();
  return code == 'email_not_confirmed' ||
      code == 'email_unconfirmed' ||
      message.contains('email not confirmed') ||
      message.contains('email is not confirmed');
}

Map<String, String> _authErrorDetails(String rawError) {
  try {
    final decoded = jsonDecode(rawError);
    if (decoded is Map) {
      final code = decoded['code'];
      final message = decoded['message'];
      if (code is String || message is String) {
        return {
          'code': code is String ? code : '',
          'message': message is String ? message : rawError,
        };
      }
    }
  } on FormatException {
    // Supabase may return plain text instead of a JSON error payload.
  }
  return {'code': '', 'message': rawError};
}

class _AgreementLink extends StatelessWidget {
  const _AgreementLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.green,
          fontFamily: 'Poppins',
          fontSize: 11,
          height: 1.4,
          decoration: TextDecoration.underline,
        ),
      ),
    ),
  );
}

class _PrivacyUsageDialog extends StatelessWidget {
  const _PrivacyUsageDialog();

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(22),
          ),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Privacy & Usage',
                      style: TextStyle(
                        color: AppColors.green,
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppColors.green),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PolicySection(
                          title: 'Privacy Policy',
                          paragraphs: [
                            'LUMINHAW processes the name and email address you provide for account creation, sign-in, email verification, password recovery, and profile display. Supabase Authentication manages your account and session. The app may also store profile information such as your display name.',
                            'If you choose to identify a plant, the selected photo is sent only after you confirm the request. The photo is sent to the configured Supabase Edge Function and Plant.ID, with PlantNet fallback, for identification; the scanner does not save that image in the app storage bucket. The scan status and returned identification result are saved in your Supabase scan history. If you choose plant-health analysis, the selected photo is uploaded to private per-user storage and a health assessment is saved to your account. Health-photo processing requires an active verified Premium entitlement.',
                            'When signed out, garden plants, care activities, and growth observations stay on this device. With a verified signed-in account, these records sync to owner-scoped Supabase tables; existing device-only records are not automatically uploaded. Library plant details saved in Settings stay on this device and are never added to My Garden automatically. Onboarding preferences remain on this device. Scan history and health assessments are stored in the configured Supabase project. Identification photos are sent for processing but are not saved to the app storage bucket; plant-health photos are uploaded to private per-user storage. LUMIN AI conversations, user messages, AI replies, and timestamps are saved in owner-scoped Supabase tables and restored when you reopen the assistant. Messages that cannot sync remain on this device until synchronization can be retried. When you send a message to LUMIN AI, the current message and up to ten recent conversation messages are sent through Supabase to Gemini. Catalog search terms may be sent to Perenual or the public GBIF API. Storage protections and account-deletion behavior depend on the project migrations and functions being deployed.',
                            'Retention periods for Supabase records and provider processing are not finalized here. Account deletion is available in Profile when the required server function is deployed; it requests deletion of the account and associated cloud data, including files in the configured private photo bucket. Local garden and journal data must also be cleared from the device. Provider-specific retention may differ and must be reviewed before release.',
                            'You may request access, correction, or deletion of personal information through the app publisher. Applicable privacy rights depend on your location. This text is a draft disclosure, not legal advice; confirm data flows, retention periods, provider terms, contact details, and legal requirements before public deployment.',
                          ],
                        ),
                        SizedBox(height: 18),
                        _PolicySection(
                          title: 'Terms of Use',
                          paragraphs: [
                            'Provide accurate registration information and keep your account credentials secure. You are responsible for activity performed through your account and should contact the publisher if you suspect unauthorized access.',
                            'Plant identification and any plant-health information are AI-assisted estimates, not guaranteed results, professional advice, or a diagnosis. Check important decisions against reliable botanical sources.',
                            'Premium features require an active entitlement verified by a trusted server. Manual GCash payments are disabled until approved merchant details, confirmed prices, receipt validation, and email review are configured. Google Play Billing and automatic GCash processing are not implemented. Subscription and payment terms must be published before accepting payment.',
                            'Do not misuse the app, attempt to access another person’s data, interfere with its services, or submit content you do not have permission to use. These are draft terms and require legal review before public deployment.',
                          ],
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Draft for review before public release.',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'Close',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          color: AppColors.green,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      for (final paragraph in paragraphs) ...[
        Text(
          paragraph,
          style: const TextStyle(
            color: AppColors.dark,
            fontSize: 12,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 10),
      ],
    ],
  );
}

class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key, this.email});

  final String? email;

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  bool _isResending = false;

  Future<void> _resendVerification() async {
    if (_isResending) return;
    if (!SupabaseBackend.isInitialized) {
      _showSetupMessage(context);
      return;
    }
    if (widget.email == null) {
      _showMessage('Open this screen from account creation to resend a link.');
      return;
    }

    setState(() => _isResending = true);
    try {
      await SupabaseAuthService.resendVerification(widget.email!);
      _showMessage('A new verification email was requested.');
    } on AuthException catch (error) {
      _showMessage(verificationEmailFailureMessage(error.message));
    } catch (error) {
      final message = _sanitizeAuthError(error.toString());
      _showMessage(
        message.isEmpty
            ? 'Could not resend the verification email.'
            : 'Could not resend the verification email: $message',
      );
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'Check your inbox',
      subtitle: 'Email verification',
      back: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Icon(
            Icons.mark_email_unread_outlined,
            color: AppColors.green,
            size: 54,
          ),
          const SizedBox(height: 20),
          Text(
            widget.email == null
                ? 'Check your inbox for the account verification link.'
                : 'We sent a verification link to ${widget.email}. Check your inbox to continue.',
            style: const TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: 24),
          if (!SupabaseBackend.isInitialized)
            SetupNotice(message: SupabaseBackend.configurationMessage),
          const SizedBox(height: 20),
          TextButton(
            onPressed: _isResending ? null : _resendVerification,
            child: Text(_isResending ? 'Sending…' : 'Resend email'),
          ),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/login'),
            child: const Text('← Back to login'),
          ),
        ],
      ),
    );
  }
}

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    if (_isSending) return;
    if (!_formKey.currentState!.validate()) return;
    if (!SupabaseBackend.isInitialized) {
      _showSetupMessage(context);
      return;
    }

    setState(() => _isSending = true);
    try {
      await SupabaseAuthService.resetPassword(_email.text);
      _showMessage('If the account exists, a reset link has been requested.');
    } on AuthException catch (error) {
      _showMessage(_sanitizeAuthError(error.message));
    } catch (error) {
      final message = _sanitizeAuthError(error.toString());
      _showMessage(
        message.isEmpty
            ? 'Could not request a reset link.'
            : 'Could not request a reset link: $message',
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'Reset password',
      subtitle: 'We will send a reset link to your email.',
      back: true,
      child: Column(
        children: [
          Form(
            key: _formKey,
            child: TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              validator: _validateEmail,
              decoration: const InputDecoration(
                labelText: 'Email address',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: _isSending ? 'Sending…' : 'Send reset link',
            onPressed: _isSending ? null : _sendResetLink,
          ),
          const SizedBox(height: 16),
          if (!SupabaseBackend.isInitialized)
            SetupNotice(message: SupabaseBackend.configurationMessage),
        ],
      ),
    );
  }
}

class UpdatePasswordPage extends StatefulWidget {
  const UpdatePasswordPage({super.key});

  @override
  State<UpdatePasswordPage> createState() => _UpdatePasswordPageState();
}

class _UpdatePasswordPageState extends State<UpdatePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;
    if (!SupabaseBackend.isInitialized ||
        SupabaseBackend.client.auth.currentSession == null) {
      _showMessage(
        'Open the password reset link before setting a new password.',
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await SupabaseAuthService.updatePassword(_password.text);
      await SupabaseAuthService.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      }
    } on AuthException catch (error) {
      _showMessage(_sanitizeAuthError(error.message));
    } catch (error) {
      final message = _sanitizeAuthError(error.toString());
      _showMessage(
        message.isEmpty
            ? 'Could not update your password.'
            : 'Could not update your password: $message',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      title: 'Choose a new password',
      subtitle: 'Set a new password for your LUMINHAW account.',
      back: true,
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              controller: _password,
              obscureText: true,
              validator: (value) => value == null || value.length < 8
                  ? 'Use at least 8 characters'
                  : null,
              decoration: const InputDecoration(
                labelText: 'New password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmation,
              obscureText: true,
              validator: (value) =>
                  value != _password.text ? 'Passwords do not match' : null,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: _isSaving ? 'Updating…' : 'Update password',
              onPressed: _isSaving ? null : _updatePassword,
            ),
            if (!SupabaseBackend.isInitialized) ...[
              const SizedBox(height: 16),
              SetupNotice(message: SupabaseBackend.configurationMessage),
            ],
          ],
        ),
      ),
    );
  }
}

class _AuthShell extends StatelessWidget {
  const _AuthShell({required this.content, required this.isSignUp});

  final Widget content;
  final bool isSignUp;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final horizontal = width < 360 ? 20.0 : 32.0;
            final available = constraints.maxHeight;
            // Screen-specific spacing: the prototype's forms do not start
            // immediately beneath the logo. On short phones, allow scrolling.
            final headingGap = isSignUp
                ? (available * 0.105).clamp(48.0, 86.0)
                : (available * 0.125).clamp(64.0, 112.0);
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(horizontal, 32, horizontal, 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (available - 64).clamp(0.0, double.infinity),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          'assets/icons/logo.png',
                          width: 32,
                          height: 38,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'LUMINHAW',
                          style: TextStyle(
                            color: AppColors.green,
                            fontFamily: 'Cinzel',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: headingGap),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: content,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.dark,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                offset: const Offset(0, 3),
                blurRadius: 3,
              ),
            ],
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscureText,
            validator: validator,
            decoration: InputDecoration(
              suffixIcon: suffix,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 11,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Color(0xFFE1E5E1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: AppColors.green),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Colors.redAccent),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: const BorderSide(color: Colors.redAccent),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String? _validateEmail(String? value) {
  if (value == null || !RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(value)) {
    return 'Enter a valid email address';
  }
  return null;
}

void _showSetupMessage(BuildContext context) {
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(SupabaseBackend.configurationMessage)));
}
