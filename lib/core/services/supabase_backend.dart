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

  static const androidPasswordResetRedirectUri =
      'com.luminhaw.plantcare://auth/reset-password';
  static String get passwordResetRedirectUri => kIsWeb
      ? Uri.base
            .replace(
              queryParameters: {
                ...Uri.base.queryParameters,
                'flow': 'password-reset',
              },
            )
            .toString()
      : androidPasswordResetRedirectUri;

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
  }) async {
    if (!_initialized) return;
    _authClientReadyForLinks = true;
    _onPasswordResetLinkError = onPasswordResetError;

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
    if (!isSupportedAuthCallback(uri)) return;
    final isPasswordReset = isPasswordResetCallback(uri);
    try {
      await client.auth.getSessionFromUrl(uri);
    } catch (_, stackTrace) {
      if (isPasswordReset) {
        consumePendingPasswordResetCallback();
        onPasswordResetError?.call();
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
    return SupabaseBackend.client.auth.updateUser(
      UserAttributes(password: password),
    );
  }

  static Future<UserResponse> updateProfileName(String name) => SupabaseBackend
      .client
      .auth
      .updateUser(UserAttributes(data: {'full_name': name.trim()}));

  static Future<void> signOut() async {
    clearPasswordRecoverySession();
    await SupabaseBackend.client.auth.signOut();
  }

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
