import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import 'app/app.dart';
import 'core/services/plan_entitlement_store.dart';
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
    });
  }
  runApp(const LuminhawApp());
}
