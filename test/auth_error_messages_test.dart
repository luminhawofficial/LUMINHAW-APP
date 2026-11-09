import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/features/authentication/auth_screens.dart';

void main() {
  test(
    'classifies confirmation delivery failure without claiming account exists',
    () {
      final message = signUpFailureMessage(
        '{"code":"unexpected_failure","message":"Error sending confirmation email"}',
      );

      expect(message, contains('could not send the confirmation email'));
      expect(message, contains('email-provider logs'));
      expect(message, contains('Authentication → Users'));
      expect(message, isNot(contains('already uses this email')));
    },
  );

  test('distinguishes existing account errors', () {
    expect(
      signUpFailureMessage(
        '{"code":"email_exists","message":"User already registered"}',
      ),
      contains('An account already uses this email'),
    );
  });

  test('detects Supabase duplicate-signup response identities', () {
    expect(signupResponseIndicatesExistingAccount(const []), isTrue);
    expect(signupResponseIndicatesExistingAccount(const ['identity']), isFalse);
    expect(signupResponseIndicatesExistingAccount(null), isFalse);
  });

  test('classifies signup rate limits', () {
    expect(
      signUpFailureMessage(
        '{"code":"over_email_send_rate_limit","message":"Too many requests"}',
      ),
      contains('temporarily rate-limited'),
    );
  });

  test('redacts email addresses from plain provider errors', () {
    expect(
      verificationEmailFailureMessage(
        'SMTP delivery to person@example.com failed',
      ),
      isNot(contains('person@example.com')),
    );
  });
}
