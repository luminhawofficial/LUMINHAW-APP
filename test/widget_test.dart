import 'dart:convert';

import 'package:flutter/material.dart'
    show
        AssetImage,
        Checkbox,
        ElevatedButton,
        Image,
        Icons,
        MaterialApp,
        Navigator,
        NavigatorState,
        NetworkImage,
        Scaffold,
        Size,
        SizedBox,
        Text,
        Theme,
        ValueKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;
import 'package:luminhaw/core/services/local_plant_data_store.dart';
import 'package:luminhaw/core/services/plan_entitlement_store.dart';
import 'package:luminhaw/features/ai_assistant/assistant_page.dart';
import 'package:luminhaw/features/garden/garden_page.dart';
import 'package:luminhaw/features/home/presentation/app_shell.dart';
import 'package:luminhaw/features/library/library_page.dart';
import 'package:luminhaw/features/subscription/subscription_pages.dart';
import 'package:luminhaw/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('dashboard displays the saved garden plant photo', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'local_garden_plant_names': ['Monstera'],
      'local_garden_plant_details': jsonEncode({
        'Monstera': {'imageUrl': 'https://example.test/monstera.jpg'},
      }),
    });
    LocalPlantDataStore.instance.retryLoad();
    await LocalPlantDataStore.instance.load();

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: HomeTab())));
    await tester.pump();

    expect(find.text('Monstera'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url ==
                'https://example.test/monstera.jpg',
      ),
      findsOneWidget,
    );
  });

  testWidgets('garden displays the saved plant photo', (tester) async {
    const imageUrl = 'https://example.test/monstera.jpg';
    SharedPreferences.setMockInitialValues({
      'local_garden_plant_names': ['Monstera'],
      'local_garden_plant_details': jsonEncode({
        'Monstera': {'imageUrl': imageUrl},
      }),
    });
    LocalPlantDataStore.instance.retryLoad();
    await LocalPlantDataStore.instance.load();

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: GardenPage())),
    );
    await tester.pump();

    expect(find.text('Monstera'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url == imageUrl,
      ),
      findsOneWidget,
    );
  });

  testWidgets('login screen lays out without errors on a narrow device', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});

    await tester.pumpWidget(const LuminhawApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login rejects invalid credentials before contacting Supabase', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await tester.pumpWidget(const LuminhawApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });

  testWidgets('sign-up validates required account fields', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await tester.pumpWidget(const LuminhawApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create an account'));
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create account'));
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Please agree to the Privacy Policy and Terms of Use to continue.',
      ),
      findsOneWidget,
    );
    expect(find.text('Enter your name'), findsNothing);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Use at least 8 characters'), findsOneWidget);
  });

  testWidgets('privacy and terms links open a dismissible signup overlay', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await tester.pumpWidget(const LuminhawApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create an account'));
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('signup-agreement-links')),
    );

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('signup-agreement-links')),
        matching: find.text('Privacy Policy'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Privacy & Usage'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsWidgets);
    expect(find.text('Terms of Use'), findsWidgets);
    expect(
      find.text('Draft for review before public release.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text("Let's grow together."), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('signup-agreement-links')),
        matching: find.text('Terms of Use'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Privacy & Usage'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('verification and password recovery routes are available', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await tester.pumpWidget(const LuminhawApp());
    await tester.pumpAndSettle();

    await openRoute(tester, '/verification');
    expect(find.text('Email verification'), findsOneWidget);
    await tester.tap(find.text('← Back to login'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address'), findsOneWidget);

    await openRoute(tester, '/update-password');
    expect(find.text('Choose a new password'), findsOneWidget);
  });

  testWidgets('verified email callback returns to the app home', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        initialRoute: '/verification',
        routes: {
          '/verification': (_) =>
              const Scaffold(body: Text('Verification pending')),
          '/home': (_) => const Scaffold(body: Text('Luminhaw home')),
          '/update-password': (_) =>
              const Scaffold(body: Text('Update password')),
        },
      ),
    );
    await tester.pumpAndSettle();

    handleAuthNavigation(AuthChangeEvent.signedIn, emailVerified: false);
    await tester.pumpAndSettle();
    expect(find.text('Verification pending'), findsOneWidget);

    handleAuthNavigation(AuthChangeEvent.signedIn, emailVerified: true);
    await tester.pumpAndSettle();
    expect(find.text('Luminhaw home'), findsOneWidget);
  });

  testWidgets(
    'library starts empty and searches online instead of sample data',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LibraryPage())),
      );
      await tester.pump();

      expect(
        find.text('Search by common, scientific, Cebuano, or Tagalog name.'),
        findsOneWidget,
      );
      expect(find.text('Monstera'), findsNothing);
      expect(find.text('Snake Plant'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('catalog request failure is not displayed as no results', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LibraryPage())),
    );
    await tester.enterText(
      find.byKey(const ValueKey('plant-catalog-search')),
      'Monstera',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('No plants match your search.'), findsNothing);
    expect(find.textContaining('Plant catalog search failed:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first launch opens intro and onboarding', (tester) async {
    await tester.pumpWidget(const LuminhawApp());
    await tester.pumpAndSettle();

    expect(find.text('Know your Plant, Nurture their Future'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Discover the green around you.'), findsOneWidget);
    expect(find.byTooltip('Notifications'), findsNothing);
    expect(find.byTooltip('Free plan'), findsNothing);
    expect(find.byTooltip('Premium plan'), findsNothing);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Keep your garden close.'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(
      find.text('Know your\nplants.\nNurture their\nfuture.'),
      findsOneWidget,
    );
    expect(
      (await SharedPreferences.getInstance()).getBool('onboarding_complete'),
      isTrue,
    );
  });

  testWidgets('home opens with functional bottom navigation', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await tester.pumpWidget(const LuminhawApp());
    await tester.pumpAndSettle();

    expect(
      find.text('Know your\nplants.\nNurture their\nfuture.'),
      findsOneWidget,
    );
    await openHome(tester);
    expect(find.textContaining('Plant lover!'), findsOneWidget);
    expect(find.text('Scan a Plant'), findsOneWidget);

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(
      find.text('Search by common, scientific, Cebuano, or Tagalog name.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Identify a plant'), findsOneWidget);
    expect(find.textContaining('only after you confirm below'), findsOneWidget);
  });

  testWidgets('scan result without provider data shows an empty state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await tester.pumpWidget(const LuminhawApp());
    await tester.pumpAndSettle();

    await openRoute(tester, '/result');

    expect(find.text('No scan result yet'), findsOneWidget);
    expect(find.text('Hibiscus'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lumin AI launcher is available on app pages', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await tester.pumpWidget(const LuminhawApp());
    await tester.pumpAndSettle();
    await openHome(tester);

    expect(find.byTooltip('Open Lumin AI'), findsOneWidget);
    await tester.tap(find.byTooltip('Open Lumin AI'));
    await tester.pumpAndSettle();

    expect(find.text('Your AI Assistant'), findsOneWidget);
    expect(find.byTooltip('Open Lumin AI'), findsNothing);
  });

  testWidgets('assistant page renders a working message entry control', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AssistantPage()));
    await tester.pumpAndSettle();

    expect(find.text('Your AI Assistant'), findsOneWidget);
    expect(
      find.text('Hi, grower! Ask me about plant care, light, or watering.'),
      findsOneWidget,
    );
    expect(find.byTooltip('Send message'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom navigation fits a narrow mobile viewport', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});

    await tester.pumpWidget(const LuminhawApp());
    await tester.pumpAndSettle();
    await openHome(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Scan').last, findsOneWidget);
  });

  testWidgets('subscription remains locked without verified entitlement', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await tester.pumpWidget(const LuminhawApp());
    await tester.pumpAndSettle();
    await openHome(tester);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subscription & payment'));
    await tester.pumpAndSettle();
    expect(find.text('PHP 49 / 30 days'), findsOneWidget);
    expect(find.text('PHP 1,499 / 365 days'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Subscribe Now'), 100);
    final subscribeButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Subscribe Now').first,
    );
    expect(subscribeButton.onPressed, isNotNull);

    expect(PlanEntitlementStore.instance.tier.value, PlanTier.free);
  });

  testWidgets('subscription pricing fits a narrow mobile viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: PremiumPage()));
    await tester.pumpAndSettle();

    expect(find.text('PHP 49 / 30 days'), findsOneWidget);
    expect(find.text('PHP 1,499 / 365 days'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile links open About and privacy disclosures', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await tester.pumpWidget(const LuminhawApp());
    await tester.pumpAndSettle();
    await openHome(tester);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Help / About'), 200);
    await tester.tap(find.text('Help / About'));
    await tester.pumpAndSettle();
    expect(find.text('Key features'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Privacy Policy / Terms'), 200);
    await tester.tap(find.text('Privacy Policy / Terms'));
    await tester.pumpAndSettle();
    expect(find.text('Photos and external services'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan and assistant screens render the supplied artwork', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_complete': true});
    await tester.pumpWidget(const LuminhawApp());
    await tester.pumpAndSettle();
    await openHome(tester);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Subscription & payment'));
    await tester.pumpAndSettle();

    expect(find.text('FREE'), findsOneWidget);
    expect(find.text('PRO'), findsOneWidget);
    expect(
      find.image(const AssetImage('assets/images/Free_logo .png')),
      findsWidgets,
    );
    expect(
      find.image(const AssetImage('assets/images/Premium_logo .png')),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open Lumin AI'));
    await tester.pumpAndSettle();

    expect(find.text('Your AI Assistant'), findsOneWidget);
    expect(
      find.image(const AssetImage('assets/images/ai_lumin_logo.png')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('typography uses the requested display, body, and brand fonts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const LuminhawApp());
    await tester.pumpAndSettle();

    final brandName = tester.widget<Text>(find.text('LUMINHAW'));
    expect(brandName.style?.fontFamily, 'Cinzel');

    final bodyTextContext = tester.element(find.text('Continue'));
    expect(
      Theme.of(bodyTextContext).textTheme.bodyMedium?.fontFamily,
      'Poppins',
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    final welcomeHeading = tester.widget<Text>(
      find.text('Know your\nplants.\nNurture their\nfuture.'),
    );
    expect(welcomeHeading.style?.fontFamily, 'PlayfairDisplay');
  });
}

Future<void> openHome(WidgetTester tester) async {
  await openRoute(tester, '/home');
}

Future<void> openRoute(WidgetTester tester, String route) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed(route);
  await tester.pumpAndSettle();
}
