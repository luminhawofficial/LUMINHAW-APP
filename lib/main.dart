import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import 'app/app.dart';
import 'core/services/app_version_service.dart';
import 'core/services/plan_entitlement_store.dart';
import 'core/services/plant_notification_service.dart';
import 'core/services/supabase_backend.dart';

export 'app/app.dart';

@visibleForTesting
void handleAuthNavigation(
  AuthChangeEvent event, {
  required bool emailVerified,
}) {
  final route = switch (event) {
    AuthChangeEvent.passwordRecovery => '/update-password',
    AuthChangeEvent.signedIn when emailVerified => '/home',
    AuthChangeEvent.signedOut => '/login',
    _ => null,
  };
  if (route == null) return;

  void navigate() {
    appNavigatorKey.currentState?.pushNamedAndRemoveUntil(route, (_) => false);
  }

  if (event == AuthChangeEvent.passwordRecovery ||
      appNavigatorKey.currentState == null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => navigate());
  } else {
    navigate();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SupabaseBackend.initialize();
  } catch (error, stackTrace) {
    SupabaseBackend.recordInitializationError(error);
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'Supabase initialization',
      ),
    );
  }
  if (SupabaseBackend.sessionRestorationError != null) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError(
          'The saved session could not be refreshed. The app will retry when online.',
        ),
        library: 'Supabase session restoration',
      ),
    );
  }
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    await AppVersionService.recordInstalledVersion(
      '${packageInfo.version}+${packageInfo.buildNumber}',
    );
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'app version update handling',
      ),
    );
  }
  if (SupabaseBackend.isInitialized) {
    SupabaseBackend.client.auth.onAuthStateChange.listen((authState) async {
      handleAuthNavigation(
        authState.event,
        emailVerified: authState.session?.user.emailConfirmedAt != null,
      );
      try {
        await PlanEntitlementStore.instance.refreshFromServer();
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'subscription entitlement refresh',
          ),
        );
      }
      try {
        await refreshEnabledCareReminders();
      } catch (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'care reminder scheduling',
          ),
        );
      }
    });
  }
  runApp(const LuminhawApp());
  try {
    await refreshEnabledCareReminders();
  } catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'care reminder scheduling',
      ),
    );
  }
}
