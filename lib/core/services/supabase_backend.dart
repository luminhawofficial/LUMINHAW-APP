import 'dart:async';
import 'dart:convert';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart'
    show
        FlutterError,
        FlutterErrorDetails,
        VoidCallback,
        kIsWeb,
        visibleForTesting;
import 'package:luminhaw/core/services/password_policy.dart';
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
  static bool _passwordResetCallbackPending = false;
  static bool _authLinkObserverStarted = false;
  static bool _authClientReadyForLinks = false;
  static final List<Uri> _queuedAuthLinks = [];
  static VoidCallback? _onPasswordResetLinkError;
  static VoidCallback? _onAuthLinkError;

  static const authWebsiteRedirectUri =
      'https://luminhawofficial.github.io/Administrator/';
  static const flutterWebOAuthRedirectUri =
      'https://luminhawofficial.github.io/LUMINHAW-APP/';
  static const androidOAuthRedirectUri =
      'com.luminhaw.plantcare://auth-callback';
  static const androidPasswordResetCompleteUri =
      'com.luminhaw.plantcare://auth-callback?password_reset=complete';
  static const androidPasswordResetRedirectUri =
      'com.luminhaw.plantcare://auth/reset-password';
  static String get passwordResetRedirectUri => authWebsiteRedirectUri;
  static String get googleOAuthRedirectUri =>
      kIsWeb ? flutterWebOAuthRedirectUri : androidOAuthRedirectUri;

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
  static String get _authRedirectUri => authWebsiteRedirectUri;

  static bool get hasPendingPasswordResetCallback =>
      _passwordResetCallbackPending;

  static bool consumePendingPasswordResetCallback() {
    final wasPending = _passwordResetCallbackPending;
    _passwordResetCallbackPending = false;
    return wasPending;
  }

  static void startAuthLinkObserver() {
    if (kIsWeb || _authLinkObserverStarted) return;
    _authLinkObserverStarted = true;
    AppLinks().uriLinkStream.listen(
      (uri) {
        if (_authClientReadyForLinks) {
          unawaited(
            _handleAuthCallback(
              uri,
              onPasswordResetError: _onPasswordResetLinkError,
            ),
          );
        } else {
          _queuedAuthLinks.add(uri);
        }
      },
      onError: (Object _, StackTrace _) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: StateError('Could not receive an authentication link.'),
            library: 'Supabase authentication links',
          ),
        );
      },
    );
  }

  static Future<void> processPendingAuthLinks({
    required VoidCallback onPasswordResetError,
    required VoidCallback onAuthLinkError,
  }) async {
    if (!_initialized) return;
    _authClientReadyForLinks = true;
    _onPasswordResetLinkError = onPasswordResetError;
    _onAuthLinkError = onAuthLinkError;

    if (kIsWeb) {
      final initialUri = await AppLinks().getInitialLink();
      if (initialUri != null) {
        await _handleAuthCallback(
          initialUri,
          onPasswordResetError: onPasswordResetError,
        );
      }
    }

    final queuedLinks = List<Uri>.of(_queuedAuthLinks);
    _queuedAuthLinks.clear();
    for (final uri in queuedLinks) {
      await _handleAuthCallback(
        uri,
        onPasswordResetError: onPasswordResetError,
      );
    }
  }

  static Future<void> _handleAuthCallback(
    Uri uri, {
    VoidCallback? onPasswordResetError,
  }) async {
    if (isPasswordResetReturnCallback(uri)) {
      try {
        await SupabaseAuthService.signOut();
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'password-reset app sign-out',
          ),
        );
      }
      return;
    }
    if (!isSupportedAuthCallback(uri)) return;
    final isPasswordReset = isPasswordResetCallback(uri);
    try {
      await client.auth.getSessionFromUrl(uri);
    } catch (_, stackTrace) {
      if (isPasswordReset) {
        consumePendingPasswordResetCallback();
        onPasswordResetError?.call();
      } else {
        _onAuthLinkError?.call();
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError(
            'The authentication link could not be completed.',
          ),
          stack: stackTrace,
          library: 'Supabase authentication link',
        ),
      );
    }
  }

  @visibleForTesting
  static bool isPasswordResetCallback(Uri uri) =>
      (uri.scheme == 'com.luminhaw.plantcare' &&
          uri.host == 'auth' &&
          uri.path == '/reset-password') ||
      (kIsWeb &&
          uri.origin == Uri.base.origin &&
          uri.queryParameters['flow'] == 'password-reset');

  @visibleForTesting
  static bool isPasswordResetReturnCallback(Uri uri) =>
      uri.scheme == 'com.luminhaw.plantcare' &&
      uri.host == 'auth-callback' &&
      uri.path.isEmpty &&
      uri.queryParameters.length == 1 &&
      uri.queryParameters['password_reset'] == 'complete' &&
      uri.fragment.isEmpty;

  @visibleForTesting
  static bool isSupportedAuthCallback(Uri uri) {
    final matchesEmailVerification =
        uri.scheme == 'com.luminhaw.plantcare' && uri.host == 'auth-callback';
    final matchesWebCallback = kIsWeb && uri.origin == Uri.base.origin;
    if (!isPasswordResetCallback(uri) &&
        !matchesEmailVerification &&
        !matchesWebCallback) {
      return false;
    }

    final fragmentParameters = Uri.splitQueryString(uri.fragment);
    final hasAuthParameter =
        uri.queryParameters.keys.any(_authCallbackParameters.contains) ||
        fragmentParameters.keys.any(_authCallbackParameters.contains);
    if (isPasswordResetCallback(uri) && hasAuthParameter) {
      _passwordResetCallbackPending = true;
    }
    return hasAuthParameter;
  }

  static const _authCallbackParameters = {
    'access_token',
    'code',
    'error',
    'error_code',
    'error_description',
  };

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
        detectSessionInUri: false,
      ),
      debug: false,
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
    final metadata = currentUser?.userMetadata;
    for (final value in [
      metadata?['full_name'],
      metadata?['name'],
      metadata?['display_name'],
    ]) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  static String? get location {
    final value = currentUser?.userMetadata?['location'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  static bool get hasEmailPasswordProvider {
    final metadata = currentUser?.appMetadata;
    final providers = metadata?['providers'];
    if (providers is List && providers.whereType<String>().contains('email')) {
      return true;
    }
    return metadata?['provider'] == 'email';
  }

  static bool get hasGoogleProvider {
    final metadata = currentUser?.appMetadata;
    final providers = metadata?['providers'];
    if (providers is List && providers.whereType<String>().contains('google')) {
      return true;
    }
    return metadata?['provider'] == 'google';
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) => SupabaseBackend.client.auth.signInWithPassword(
    email: email.trim(),
    password: password,
  );

  static Future<bool> signInWithGoogle() =>
      SupabaseBackend.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: SupabaseBackend.googleOAuthRedirectUri,
      );

  static Future<void> ensureCurrentUserProfile() async {
    final user = currentUser;
    if (user == null) return;

    final client = SupabaseBackend.client;
    final existing = await client
        .from('profiles')
        .select('id')
        .eq('id', user.id)
        .maybeSingle();
    if (existing != null) return;

    final metadata = user.userMetadata;
    final displayName =
        [metadata?['full_name'], metadata?['name'], metadata?['display_name']]
            .whereType<String>()
            .map((value) => value.trim())
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    await client.from('profiles').upsert({
      'id': user.id,
      'display_name': displayName,
    }, onConflict: 'id');
  }

  static Future<void> refreshSessionIfExpired() async {
    final auth = SupabaseBackend.client.auth;
    if (auth.currentSession?.isExpired ?? false) {
      await auth.refreshSession();
    }
  }

  static Future<User?> refreshCurrentSession() async {
    final auth = SupabaseBackend.client.auth;
    if (auth.currentSession == null) return null;
    final response = await auth.refreshSession();
    return response.user ?? auth.currentUser;
  }

  static Future<AuthResponse> signUp({
    required String name,
    required String email,
    required String password,
  }) {
    _validatePassword(password);
    return SupabaseBackend.client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: SupabaseBackend._authRedirectUri,
      data: {'full_name': name.trim()},
    );
  }

  static Future<void> resendVerification(String email) =>
      SupabaseBackend.client.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: SupabaseBackend._authRedirectUri,
      );

  static Future<void> resetPassword(String email) =>
      SupabaseBackend.client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: SupabaseBackend.passwordResetRedirectUri,
      );

  static String? _verifiedRecoveryUserId;

  static bool get hasVerifiedPasswordRecoverySession {
    final session = SupabaseBackend.isInitialized
        ? SupabaseBackend.client.auth.currentSession
        : null;
    return session != null &&
        !session.isExpired &&
        session.user.id == _verifiedRecoveryUserId;
  }

  static void recordPasswordRecoverySession(Session? session) {
    _verifiedRecoveryUserId = session != null && !session.isExpired
        ? session.user.id
        : null;
    SupabaseBackend.consumePendingPasswordResetCallback();
  }

  static void clearPasswordRecoverySession() {
    _verifiedRecoveryUserId = null;
    SupabaseBackend.consumePendingPasswordResetCallback();
  }

  static Future<UserResponse> updatePassword(String password) {
    if (!hasVerifiedPasswordRecoverySession) {
      throw StateError('A verified password recovery session is required.');
    }
    _validatePassword(password);
    return SupabaseBackend.client.auth.updateUser(
      UserAttributes(password: password),
    );
  }

  static Future<UserResponse> changePassword({
    required String newPassword,
    String? currentPassword,
  }) async {
    final client = SupabaseBackend.client;
    final user = currentUser;
    if (user == null || client.auth.currentSession == null) {
      throw StateError('Sign in before changing your password.');
    }
    _validatePassword(newPassword);

    if (hasEmailPasswordProvider) {
      final email = user.email;
      if (email == null || currentPassword == null || currentPassword.isEmpty) {
        throw StateError('Enter your current password to continue.');
      }
      final reauthenticated = await client.auth.signInWithPassword(
        email: email,
        password: currentPassword,
      );
      if (reauthenticated.user?.id != user.id ||
          reauthenticated.session == null) {
        throw StateError('Could not verify the current account.');
      }
    }

    return client.auth.updateUser(
      UserAttributes(
        password: newPassword,
        currentPassword: hasEmailPasswordProvider ? currentPassword : null,
      ),
    );
  }

  static Future<UserResponse> updateProfile({
    required String name,
    required String location,
  }) async {
    final client = SupabaseBackend.client;
    final user = currentUser;
    if (user == null || client.auth.currentSession == null) {
      throw StateError('Sign in before updating your profile.');
    }
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Must not be empty.');
    }

    final response = await client.auth.updateUser(
      UserAttributes(
        data: {
          'full_name': normalizedName,
          'location': location.trim(),
        },
      ),
    );
    if (user.emailConfirmedAt != null) {
      try {
        await client.from('profiles').upsert({
          'id': user.id,
          'display_name': normalizedName,
        }, onConflict: 'id');
      } catch (error) {
        throw StateError(
          'Your profile details were updated, but the profile record could '
          'not be synchronized: $error',
        );
      }
    }
    return response;
  }

  static Future<void> signOut() async {
    clearPasswordRecoverySession();
    await SupabaseBackend.client.auth.signOut();
  }

  static void _validatePassword(String password) {
    final error = PasswordPolicy.validate(password);
    if (error != null) throw ArgumentError(error);
  }

  static Future<void> deleteAccount({String? password}) async {
    final client = SupabaseBackend.client;
    final user = currentUser;
    if (user == null || client.auth.currentSession == null) {
      throw StateError('Sign in before deleting your account.');
    }

    if (!hasGoogleProvider || hasEmailPasswordProvider) {
      final email = user.email;
      if (email == null || password == null || password.isEmpty) {
        throw StateError('Verify your account password before deleting it.');
      }
      final reauthenticated = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (reauthenticated.user?.id != user.id ||
          reauthenticated.session == null) {
        throw StateError('Could not verify the account for deletion.');
      }
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
        return 'Sign in again just before deleting your account, then retry within five minutes.';
      }
    }
    return 'Account deletion failed. Please try again.';
  }
}
