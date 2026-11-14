import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/services/password_policy.dart';

void main() {
  test('accepts a password meeting every requirement', () {
    expect(PasswordPolicy.isValid('Luminhaw@2026'), isTrue);
    expect(PasswordPolicy.validate('Luminhaw@2026'), isNull);
  });

  test(
    'rejects a password missing uppercase, lowercase, number, or symbol',
    () {
      expect(PasswordPolicy.validate('luminhaw@2026'), contains('uppercase'));
      expect(PasswordPolicy.validate('LUMINHAW@2026'), contains('lowercase'));
      expect(PasswordPolicy.validate('Luminhaw@'), contains('number'));
      expect(
        PasswordPolicy.validate('Luminhaw2026'),
        contains('special symbol'),
      );
    },
  );

  test('rejects short passwords and whitespace as the only symbol', () {
    expect(PasswordPolicy.validate('Lum@26'), 'Use at least 8 characters');
    expect(PasswordPolicy.hasSpecialCharacter('Luminhaw2026 '), isFalse);
  });

  test('rejects each example password that violates the policy', () {
    for (final password in [
      'luminhaw123',
      'LUMINHAW@123',
      'Luminhaw@',
      'Luminhaw2026',
      'Lum@26',
    ]) {
      expect(PasswordPolicy.isValid(password), isFalse, reason: password);
    }
  });
}
