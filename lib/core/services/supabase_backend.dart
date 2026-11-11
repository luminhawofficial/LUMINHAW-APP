import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseBackend {
  SupabaseBackend._();

  static const _url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ccxzjjsxggrxiaaehxxu.supabase.co',
  );
  static const _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _defaultPublishableKey =
      'sb_publishable_Qbn3NBaKGonv84Ud-KDszQ_owgaWLSl';

  static bool _initialized = false;
  static Object? _initializationError;
  static Object? _sessionRestorationError;
  static Future<void>? _initialization;

  static String get _publicKey {
    if (_publishableKey.trim().isNotEmpty) return _publishableKey.trim();
    if (_anonKey.trim().isNotEmpty) return _anonKey.trim();
    return _defaultPublishableKey;
  }

  static bool get isConfigured =>
      _url.trim().isNotEmpty && _publicKey.isNotEmpty;
  static bool get isInitialized => _initialized;
  static Object? get initializationError => _initializationError;
  static Object? get sessionRestorationError => _sessionRestorationError;
  static String get _authRedirectUri =>
      kIsWeb ? Uri.base.origin : 'com.luminhaw.plantcare://auth-callback';

  static String get configurationMessage {
    if (_initializationError != null) {
      return 'Supabase could not be initialized. Check the project URL and public key, then restart the app.';
    }
    return 'Supabase is not configured. Provide SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY) with --dart-define to enable account features.';
  }

  static Future<void> initialize() => _initialization ??= _initialize();

  static Future<void> _initialize() async {
    final url = _url.trim();
    final publicKey = _publicKey;
    if (url.isEmpty && publicKey.isEmpty) return;
    if (url.isEmpty || publicKey.isEmpty) {
      throw StateError('SUPABASE_URL and a public Supabase key are required.');
    }

    await Supabase.initialize(
      url: url,
      publishableKey: publicKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        autoRefreshToken: true,
        persistSession: true,
      ),
    );

    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session?.isExpired ?? false) {
      try {
        await client.auth.refreshSession();
      } catch (error) {
        if (client.auth.currentSession != null) {
          _sessionRestorationError = error;
        }
      }
    }
    _initialized = true;
  }

  static void recordInitializationError(Object error) {
    _initializationError = error;
  }

  static SupabaseClient get client {
    if (!_initialized) {
      throw StateError(configurationMessage);
    }
    return Supabase.instance.client;
  }
}

class SupabaseAuthService {
  SupabaseAuthService._();

  static User? get currentUser => SupabaseBackend.isInitialized
      ? SupabaseBackend.client.auth.currentUser
      : null;

  static String? get displayName {
    final user = currentUser;
    final name = user?.userMetadata?['full_name'];
    return name is String && name.trim().isNotEmpty ? name.trim() : null;
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) => SupabaseBackend.client.auth.signInWithPassword(
    email: email.trim(),
    password: password,
  );

  static Future<void> refreshSessionIfExpired() async {
    final auth = SupabaseBackend.client.auth;
    if (auth.currentSession?.isExpired ?? false) {
      await auth.refreshSession();
    }
  }

  static Future<AuthResponse> signUp({
    required String name,
    required String email,
    required String password,
  }) => SupabaseBackend.client.auth.signUp(
    email: email.trim(),
    password: password,
    emailRedirectTo: SupabaseBackend._authRedirectUri,
    data: {'full_name': name.trim()},
  );

  static Future<void> resendVerification(String email) =>
      SupabaseBackend.client.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: SupabaseBackend._authRedirectUri,
      );

  static Future<void> resetPassword(String email) =>
      SupabaseBackend.client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: SupabaseBackend._authRedirectUri,
      );

  static Future<UserResponse> updatePassword(String password) => SupabaseBackend
      .client
      .auth
      .updateUser(UserAttributes(password: password));

  static Future<UserResponse> updateProfileName(String name) => SupabaseBackend
      .client
      .auth
      .updateUser(UserAttributes(data: {'full_name': name.trim()}));

  static Future<void> signOut() => SupabaseBackend.client.auth.signOut();

  static Future<void> deleteAccount({required String password}) async {
    final client = SupabaseBackend.client;
    final user = currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw StateError('Sign in before deleting your account.');
    }

    final reauthenticated = await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (reauthenticated.user?.id != user.id ||
        reauthenticated.session == null) {
      throw StateError('Could not verify the account for deletion.');
    }

    try {
      final response = await client.functions.invoke('delete-account');
      if (response.status < 200 || response.status >= 300) {
        throw StateError(_deletionErrorMessage(response.data));
      }
    } on FunctionException catch (error) {
      throw StateError(_deletionErrorMessage(error.details));
    }
    await client.auth.signOut();
  }

  static String _deletionErrorMessage(Object? details) {
    Object? payload = details;
    if (payload is String) {
      try {
        payload = jsonDecode(payload);
      } on FormatException {
        return 'Account deletion failed. Please try again.';
      }
    }
    if (payload is Map) {
      final error = payload['error'];
      if (error is Map && error['code'] == 'reauthentication_required') {
        return 'Verify your password again before deleting your account.';
      }
    }
    return 'Account deletion failed. Please try again.';
  }
}
