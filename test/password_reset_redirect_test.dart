import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/services/supabase_backend.dart';

void main() {
  setUp(() {
    SupabaseBackend.consumePendingPasswordResetCallback();
  });

  test('uses the auth website and preserves the Android callback URI', () {
    expect(
      SupabaseBackend.androidPasswordResetRedirectUri,
      'com.luminhaw.plantcare://auth/reset-password',
    );
    expect(
      SupabaseBackend.passwordResetRedirectUri,
      'https://luminhawofficial.github.io/Administrator/',
    );
  });

  test('accepts reset callbacks and tracks recovery-link failures', () {
    final resetCallback = Uri.parse(
      'com.luminhaw.plantcare://auth/reset-password?code=example',
    );

    expect(SupabaseBackend.isSupportedAuthCallback(resetCallback), isTrue);
    expect(SupabaseBackend.hasPendingPasswordResetCallback, isTrue);
    expect(SupabaseBackend.consumePendingPasswordResetCallback(), isTrue);
  });

  test('continues accepting the existing email-verification callback', () {
    expect(
      SupabaseBackend.isSupportedAuthCallback(
        Uri.parse('com.luminhaw.plantcare://auth-callback?code=example'),
      ),
      isTrue,
    );
  });

  test('rejects unsupported callback paths and unrelated links', () {
    expect(
      SupabaseBackend.isSupportedAuthCallback(
        Uri.parse('com.luminhaw.plantcare://auth/other?code=example'),
      ),
      isFalse,
    );
    expect(
      SupabaseBackend.isSupportedAuthCallback(
        Uri.parse('https://example.com/?code=example'),
      ),
      isFalse,
    );
  });
}
