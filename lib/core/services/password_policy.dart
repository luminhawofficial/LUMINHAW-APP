class PasswordPolicy {
  PasswordPolicy._();

  static bool hasMinimumLength(String value) => value.length >= 8;
  static bool hasUppercase(String value) => RegExp(r'[A-Z]').hasMatch(value);
  static bool hasLowercase(String value) => RegExp(r'[a-z]').hasMatch(value);
  static bool hasNumber(String value) => RegExp(r'[0-9]').hasMatch(value);
  static bool hasSpecialCharacter(String value) =>
      RegExp(r'[^A-Za-z0-9\s]').hasMatch(value);

  static bool isValid(String value) =>
      hasMinimumLength(value) &&
      hasUppercase(value) &&
      hasLowercase(value) &&
      hasNumber(value) &&
      hasSpecialCharacter(value);

  static String? validate(String? value) {
    final password = value ?? '';
    if (!hasMinimumLength(password)) return 'Use at least 8 characters';
    if (!hasUppercase(password)) return 'Add at least one uppercase letter';
    if (!hasLowercase(password)) return 'Add at least one lowercase letter';
    if (!hasNumber(password)) return 'Add at least one number';
    if (!hasSpecialCharacter(password)) {
      return 'Add at least one special symbol';
    }
    return null;
  }
}
