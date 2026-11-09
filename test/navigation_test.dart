import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/app/router.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';
import 'package:luminhaw/core/services/saved_plant_details_store.dart';
import 'package:luminhaw/features/garden/add_garden_plant_page.dart';
import 'package:luminhaw/features/garden/garden_page.dart';
import 'package:luminhaw/features/growth_tracker/growth_tracker_page.dart';
import 'package:luminhaw/features/settings/settings_page.dart';
import 'package:luminhaw/features/settings/saved_plant_details_page.dart';
import 'package:luminhaw/features/profile/profile_page.dart';
import 'package:luminhaw/features/subscription/subscription_pages.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('header notification and plan badge open their pages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(body: AppHeader()),
        routes: {
          '/notifications': (_) => const NotificationsPage(),
          '/premium': (_) => const PremiumPage(),
        },
      ),
    );

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text("You're all caught up"), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Free plan'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock more with LUMINHAW Premium'), findsOneWidget);
  });

  testWidgets('garden links to growth tracking and manual plant registration', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(body: GardenPage()),
        routes: {
          '/growth': (_) => const GrowthTrackerPage(),
          '/add-plant': (_) => const AddGardenPlantPage(),
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Track plant growth'));
    await tester.pumpAndSettle();
    expect(find.text('Track plant growth'), findsWidgets);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a plant'));
    await tester.pumpAndSettle();
    expect(find.text('Add a plant to track'), findsOneWidget);
  });

  testWidgets('Settings does not list saved plant details', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: const Scaffold(body: SettingsPage())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Saved plant details'), findsNothing);
    expect(find.text('Care reminders'), findsOneWidget);
    expect(find.text('Change password'), findsOneWidget);
  });

  testWidgets('Profile opens saved plant details', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const Scaffold(body: ProfilePage()),
        routes: {
          '/saved-plant-details': (_) =>
              SavedPlantDetailsPage(store: SavedPlantDetailsStore()),
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saved plant details'));
    await tester.pumpAndSettle();

    expect(find.text('No saved plant details yet'), findsOneWidget);
    expect(find.textContaining('Not in My Garden'), findsOneWidget);
  });

  testWidgets('logout confirmation requires an explicit choice', (
    tester,
  ) async {
    Future<bool>? confirmation;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => confirmation = confirmLogout(context),
              child: const Text('Open logout confirmation'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open logout confirmation'));
    await tester.pumpAndSettle();
    expect(find.text('Log out account?'), findsOneWidget);
    expect(find.text('Stay here'), findsOneWidget);
    expect(find.text('Yes, log out'), findsOneWidget);

    await tester.tap(find.text('Stay here'));
    await tester.pumpAndSettle();
    expect(await confirmation, isFalse);

    await tester.tap(find.text('Open logout confirmation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, log out'));
    await tester.pumpAndSettle();
    expect(await confirmation, isTrue);
  });

  test('plant learning has one Library route, not a Know page', () {
    expect(LuminhawRouter.routes.containsKey('/library'), isTrue);
    expect(LuminhawRouter.routes.containsKey('/know-your-plant'), isFalse);
  });
}
