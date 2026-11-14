import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luminhaw/app/router.dart';
import 'package:luminhaw/core/widgets/app_ui.dart';
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:luminhaw/core/services/saved_plant_details_store.dart';
import 'package:luminhaw/features/garden/add_garden_plant_page.dart';
import 'package:luminhaw/features/garden/garden_page.dart';
import 'package:luminhaw/features/home/presentation/app_shell.dart';
import 'package:luminhaw/features/growth_tracker/growth_tracker_page.dart';
import 'package:luminhaw/features/settings/settings_page.dart';
import 'package:luminhaw/features/settings/saved_plant_details_page.dart';
import 'package:luminhaw/features/profile/profile_page.dart';
import 'package:luminhaw/features/subscription/subscription_pages.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalPlantDataStore.instance.retryLoad();
  });

  testWidgets('header actions align to the right edge of their container', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(512, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AppHeader())),
    );
    await tester.pumpAndSettle();

    final planBadge = tester.getRect(find.byType(PlanBadge));
    expect(planBadge.right, 492);
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
    expect(find.text('System announcements'), findsOneWidget);
    expect(
      find.textContaining('System announcements could not be loaded:'),
      findsOneWidget,
    );

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Basic plan'));
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

    await tester.tap(find.text('Saved plants'));
    await tester.pumpAndSettle();

    expect(find.text('No saved plant details yet'), findsOneWidget);
    expect(find.textContaining('Not in My Garden'), findsOneWidget);
  });

  testWidgets('Profile edit action responds to a tap when signed out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(initialRoute: '/profile', routes: LuminhawRouter.routes),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('profile-edit-button')));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back.'), findsOneWidget);
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

  testWidgets('Lumin AI launcher is hidden during onboarding and sign-in', (
    tester,
  ) async {
    for (final route in [
      '/',
      '/welcome',
      '/onboarding',
      '/login',
      '/signup',
      '/verification',
      '/forgot',
      '/update-password',
    ]) {
      await tester.pumpWidget(
        MaterialApp(initialRoute: route, routes: LuminhawRouter.routes),
      );
      await tester.pumpAndSettle();

      expect(
        find.byTooltip('Open Lumin AI'),
        findsNothing,
        reason: 'The launcher should be hidden on $route.',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Lumin AI launcher is visible on the dashboard and features', (
    tester,
  ) async {
    for (final route in [
      '/home',
      '/edit-profile',
      '/scan',
      '/result',
      '/history',
      '/garden',
      '/add-plant',
      '/notifications',
      '/settings',
      '/saved-plant-details',
      '/care',
      '/growth',
      '/add-entry',
      '/health',
      '/premium',
      '/payment',
      '/library',
      '/profile',
      '/about',
      '/privacy',
    ]) {
      await tester.pumpWidget(
        MaterialApp(initialRoute: route, routes: LuminhawRouter.routes),
      );
      await tester.pumpAndSettle();

      expect(
        find.byTooltip('Open Lumin AI'),
        findsOneWidget,
        reason: 'The launcher should be visible on $route.',
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('Lumin AI stays visible when switching between app pages', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(initialRoute: '/home', routes: LuminhawRouter.routes),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open Lumin AI'), findsOneWidget);

    for (final tab in ['Library', 'Garden', 'Profile', 'Home']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Open Lumin AI'),
        findsOneWidget,
        reason: 'The launcher should remain visible after switching to $tab.',
      );
    }

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final settingsRoute = navigator.pushNamed('/settings');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open Lumin AI'), findsOneWidget);

    navigator.pop();
    await tester.pumpAndSettle();
    await settingsRoute;
    expect(find.byTooltip('Open Lumin AI'), findsOneWidget);

    final libraryRoute = navigator.pushNamed('/library');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open Lumin AI'), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();
    await libraryRoute;
    expect(find.byTooltip('Open Lumin AI'), findsOneWidget);
  });

  testWidgets('Lumin AI is part of the authenticated shell itself', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AppShell()));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Open Lumin AI'), findsOneWidget);

    for (final tab in ['Library', 'Garden', 'Profile', 'Home']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Open Lumin AI'), findsOneWidget);
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('Lumin AI remains visible after returning from the plan page', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(initialRoute: '/home', routes: LuminhawRouter.routes),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open Lumin AI'), findsOneWidget);

    await tester.tap(find.byTooltip('Basic plan'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock more with LUMINHAW Premium'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pumpAndSettle();

    expect(find.text('Home').last, findsOneWidget);
    expect(find.byTooltip('Open Lumin AI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lumin AI launcher sits above the dashboard navigation bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(initialRoute: '/home', routes: LuminhawRouter.routes),
    );
    await tester.pumpAndSettle();

    final launcher = tester.getCenter(find.byTooltip('Open Lumin AI'));
    final homeTab = tester.getCenter(find.text('Home').last);
    expect(launcher.dy, lessThan(homeTab.dy));
  });

  testWidgets(
    'Lumin AI launcher remains after returning from profile editing',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(initialRoute: '/home', routes: LuminhawRouter.routes),
      );
      await tester.pumpAndSettle();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      final editProfileRoute = navigator.pushNamed('/edit-profile');
      await tester.pumpAndSettle();
      expect(find.byTooltip('Open Lumin AI'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await editProfileRoute;

      expect(find.byTooltip('Open Lumin AI'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('plant learning has one Library route, not a Know page', () {
    expect(LuminhawRouter.routes.containsKey('/library'), isTrue);
    expect(LuminhawRouter.routes.containsKey('/know-your-plant'), isFalse);
  });
}
