import 'package:shared_preferences/shared_preferences.dart';

class AppVersionService {
  AppVersionService._();

  static const _installedVersionKey = 'installed_app_version';

  static Future<void> recordInstalledVersion(String currentVersion) async {
    final normalizedVersion = currentVersion.trim();
    if (normalizedVersion.isEmpty) {
      throw ArgumentError.value(currentVersion, 'currentVersion');
    }

    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _installedVersionKey,
      normalizedVersion,
    );
    if (!saved) {
      throw StateError('The installed app version could not be saved.');
    }
  }
}
