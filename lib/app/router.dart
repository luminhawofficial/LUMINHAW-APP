import 'package:flutter/material.dart';
import 'package:luminhaw/core/models/plant_record.dart';
import 'package:luminhaw/core/services/plant_identification_service.dart';
import 'package:luminhaw/features/ai_assistant/assistant_page.dart';
import 'package:luminhaw/features/ai_assistant/ai_search_history_page.dart';
import 'package:luminhaw/features/ai_assistant/lumin_assistant_overlay.dart';
import 'package:luminhaw/features/authentication/auth_screens.dart';
import 'package:luminhaw/features/care_guide/care_guide_page.dart';
import 'package:luminhaw/features/garden/garden_page.dart';
import 'package:luminhaw/features/garden/add_garden_plant_page.dart';
import 'package:luminhaw/features/growth_tracker/growth_tracker_page.dart';
import 'package:luminhaw/features/health_checker/health_checker_page.dart';
import 'package:luminhaw/features/home/presentation/app_shell.dart';
import 'package:luminhaw/features/information/information_pages.dart';
import 'package:luminhaw/features/library/library_page.dart';
import 'package:luminhaw/features/onboarding/onboarding_flow.dart';
import 'package:luminhaw/features/profile/edit_profile_page.dart';
import 'package:luminhaw/features/scan_results/scan_result_page.dart';
import 'package:luminhaw/features/scanner/scan_history_page.dart';
import 'package:luminhaw/features/scanner/scanner_page.dart';
import 'package:luminhaw/features/settings/settings_page.dart';
import 'package:luminhaw/features/settings/saved_plant_details_page.dart';
import 'package:luminhaw/features/subscription/subscription_pages.dart';
import 'package:luminhaw/features/subscription/premium_payment_page.dart';

class LuminhawRouter {
  LuminhawRouter._();

  static const initialRoute = '/';

  static Map<String, WidgetBuilder> get routes => {
    '/': (_) => const AppEntry(),
    '/welcome': (_) => const WelcomePage(),
    '/onboarding': (_) => const OnboardingPage(),
    '/home': (_) => const AppShell(),
    '/login': (_) => const LoginPage(),
    '/signup': (_) => const SignUpPage(),
    '/verification': (context) =>
        VerificationPage(email: _emailArgument(context)),
    '/forgot': (_) => const ForgotPasswordPage(),
    '/update-password': (_) => const UpdatePasswordPage(),
    '/scan': _assistantOverlay((_) => const ScannerPage()),
    '/result': _assistantOverlay(
      (context) => ScanResultPage(
        plant: _plantArgument(context),
        scanResult: _scanResultArgument(context),
      ),
    ),
    '/history': _assistantOverlay((_) => const ScanHistoryPage()),
    '/garden': _assistantOverlay(
      (_) => Scaffold(body: SafeArea(child: const GardenPage())),
    ),
    '/add-plant': _assistantOverlay((_) => const AddGardenPlantPage()),
    '/notifications': _assistantOverlay((_) => const NotificationsPage()),
    '/settings': _assistantOverlay((_) => const SettingsPage()),
    '/saved-plant-details': _assistantOverlay(
      (context) => SavedPlantDetailsPage(plant: _plantArgument(context)),
    ),
    '/edit-profile': _assistantOverlay((_) => const EditProfilePage()),
    '/care': _assistantOverlay(
      (context) => CareGuidePage(plant: _plantArgument(context)),
    ),
    '/growth': _assistantOverlay(
      (context) => GrowthTrackerPage(plant: _plantArgument(context)),
    ),
    '/add-entry': _assistantOverlay(
      (context) => AddGrowthEntryPage(plant: _plantArgument(context)),
    ),
    '/health': _assistantOverlay(
      (context) => HealthCheckerPage(plant: _plantArgument(context)),
    ),
    '/premium': _assistantOverlay((_) => const PremiumPage()),
    '/payment': _assistantOverlay((_) => const PremiumPaymentPage()),
    '/ai-history': _assistantOverlay((_) => const AiSearchHistoryPage()),
    '/assistant': (context) =>
        AssistantPage(conversationId: _conversationArgument(context)),
    '/assistant/new': (_) => const AssistantPage(startNewChat: true),
    '/library': (_) => const AppShell(initialTab: 1),
    '/profile': (_) => const AppShell(initialTab: 4),
    '/about': _assistantOverlay((_) => const AboutPage()),
    '/privacy': _assistantOverlay((_) => const PrivacyPage()),
  };

  static WidgetBuilder _assistantOverlay(
    WidgetBuilder pageBuilder, {
    bool aboveBottomBar = false,
  }) =>
      (context) => LuminAssistantOverlay(
        aboveBottomBar: aboveBottomBar,
        child: pageBuilder(context),
      );

  static PlantRecord? _plantArgument(BuildContext context) {
    final argument = ModalRoute.of(context)?.settings.arguments;
    return argument is PlantRecord ? argument : null;
  }

  static PlantIdentificationResult? _scanResultArgument(BuildContext context) {
    final argument = ModalRoute.of(context)?.settings.arguments;
    return argument is PlantIdentificationResult ? argument : null;
  }

  static String? _emailArgument(BuildContext context) {
    final argument = ModalRoute.of(context)?.settings.arguments;
    return argument is String ? argument : null;
  }

  static String? _conversationArgument(BuildContext context) {
    final argument = ModalRoute.of(context)?.settings.arguments;
    return argument is String ? argument : null;
  }

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    if (settings.name == '/plant' && settings.arguments is PlantRecord) {
      return MaterialPageRoute<void>(
        builder: _assistantOverlay(
          (_) => PlantDetailPage(plant: settings.arguments! as PlantRecord),
        ),
        settings: settings,
      );
    }
    return null;
  }
}
