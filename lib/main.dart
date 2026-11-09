import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;

import 'app/app.dart';
import 'core/services/plan_entitlement_store.dart';
import 'core/services/supabase_backend.dart';

export 'app/app.dart';

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
      if (authState.event == AuthChangeEvent.passwordRecovery) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          appNavigatorKey.currentState?.pushNamedAndRemoveUntil(
            '/update-password',
            (_) => false,
          );
        });
      }
    });
  }
  runApp(const LuminhawApp());
}
