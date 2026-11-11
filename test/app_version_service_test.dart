import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/core/services/app_version_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('first install records the version', () async {
    await AppVersionService.recordInstalledVersion('1.0.0+1');
    expect(
      (await SharedPreferences.getInstance()).getString(
        'installed_app_version',
      ),
      '1.0.0+1',
    );
  });

  test(
    'app update preserves session storage and records the new version',
    () async {
      SharedPreferences.setMockInitialValues({
        'installed_app_version': '1.0.0+1',
      });
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('sb-project-auth-token', 'persisted-session');
      await AppVersionService.recordInstalledVersion('1.0.1+2');

      expect(preferences.getString('installed_app_version'), '1.0.1+2');
      expect(
        preferences.getString('sb-project-auth-token'),
        'persisted-session',
      );
    },
  );
}
