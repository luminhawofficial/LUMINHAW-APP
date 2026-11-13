# LUMINHAW Navigation Explanation

This document describes how screens and tabs are opened in the LUMINHAW
Flutter app. Navigation uses Flutter's named-route `Navigator`, with route
definitions in `lib/app/router.dart`.

## Navigation overview

```text
main()
  └── LuminhawApp (MaterialApp)
        └── / (AppEntry)
              ├── valid saved aSupabase session ──> AppShell
              ├── onboarding complete ──────────> LoginPage
              └── first launch ─────────────────> IntroPage

AppShell (/home)
  ├── Home
  ├── Library
  ├── Scan
  ├── Garden
  └── Profile
```

The five main tabs are held in an `IndexedStack`; choosing a tab changes the
selected index rather than pushing another route. Other screens, such as
profile settings, plant details, and AI history, are opened as named routes.

## 1. App setup and route registration

`LuminhawApp` configures the initial route, route table, dynamic route handler,
and a navigator key:

```dart
return MaterialApp(
  navigatorKey: appNavigatorKey,
  initialRoute: widget.initialRoute,
  routes: LuminhawRouter.routes,
  onGenerateRoute: LuminhawRouter.onGenerateRoute,
);
```

The normal initial route is `/`. `LuminhawRouter.routes` maps route names to
page builders. A simplified example from `lib/app/router.dart`:

```dart
static Map<String, WidgetBuilder> get routes => {
  '/': (_) => const AppEntry(),
  '/welcome': (_) => const WelcomePage(),
  '/home': (_) => const AppShell(),
  '/login': (_) => const LoginPage(),
  '/profile': (_) => const AppShell(initialTab: 4),
  '/ai-history': _assistantOverlay((_) => const AiSearchHistoryPage()),
  '/assistant': (context) =>
      AssistantPage(conversationId: _conversationArgument(context)),
  '/assistant/new': (_) => const AssistantPage(startNewChat: true),
};
```

Some routes wrap their page with `LuminAssistantOverlay` so the floating AI
launcher is available on that screen. Authentication and onboarding screens
do not use that wrapper.

## 2. Choosing the first screen

The `/` route builds `AppEntry` in `lib/features/onboarding/onboarding_flow.dart`.
It reads the saved onboarding preference and checks for a valid restored
Supabase session:

```dart
if (session != null && !session.isExpired) {
  return const AppShell();
}
return snapshot.data! ? const LoginPage() : const IntroPage();
```

On a first launch, the intro opens onboarding. Completing onboarding saves the
preference and replaces the current route stack with `/welcome`:

```dart
await preferences.setBool('onboarding_complete', true);
if (context.mounted) {
  Navigator.pushNamedAndRemoveUntil(context, '/welcome', (_) => false);
}
```

The welcome screen offers sign-in and account creation. A later launch with a
valid saved session goes directly to `AppShell`.

## 3. Opening screens and passing data

Use `Navigator.pushNamed` when the current screen should remain underneath the
new page. The Back button can then return to it:

```dart
Navigator.pushNamed(context, '/ai-history');
```

Pass route data through `arguments`. For example, the library sends a
`PlantRecord` to the plant-details route:

```dart
Navigator.pushNamed(context, '/plant', arguments: plant);
```

`/plant` is created by `onGenerateRoute` in `lib/app/router.dart`, which checks
that the argument is a `PlantRecord`. Other routes extract their supported
argument types in helper methods, such as `/verification` (email),
`/result` (plant and identification result), and `/assistant` (conversation
ID).

## 4. Replacing the navigation stack

After sign-in or sign-out, the old pages should not remain available through
Back. Use `pushNamedAndRemoveUntil` with a predicate that returns `false` to
remove every previous route:

```dart
Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
```

`lib/main.dart` listens to Supabase authentication events and can navigate
without a page `BuildContext` by using `appNavigatorKey`:

```dart
final route = switch (event) {
  AuthChangeEvent.passwordRecovery => '/update-password',
  AuthChangeEvent.signedIn when emailVerified => '/home',
  AuthChangeEvent.signedOut => '/login',
  _ => null,
};

if (route != null) {
  appNavigatorKey.currentState?.pushNamedAndRemoveUntil(
    route,
    (_) => false,
  );
}
```

The login screen also navigates to `/home` after a successful verified sign-in.
Password recovery opens `/update-password`; the user can then complete the
password update flow.

## 5. Switching between the five main tabs

`AppShell` creates the Home, Library, Scan, Garden, and Profile pages once and
places them in an `IndexedStack`. A tab tap updates `_index`:

```dart
onTap: () => setState(() => _index = 1),
```

The selected tab is displayed by:

```dart
IndexedStack(index: _index, children: _tabs)
```

Because this is not a route push, changing tabs does not add pages to the
navigation stack. The inactive tab widgets remain mounted, preserving their
state while the student moves between tabs. `/library` and `/profile` are
routes that open `AppShell` with a different initial tab.

## 6. LUMIN AI navigation

Feature routes wrapped in `LuminAssistantOverlay` show the floating AI button.
Tapping it pushes `/assistant`, keeping the current page beneath the chat.

The AI history page can pass a selected conversation ID to `/assistant` to
restore that conversation. A separate `/assistant/new` route explicitly starts
a new chat:

```dart
Navigator.pushNamed(
  context,
  '/assistant',
  arguments: conversationId,
);

Navigator.pushNamed(context, '/assistant/new');
```

The AI history page is available at `/ai-history` from Profile. Opening a
conversation uses a normal route push, so Back returns to the history list.

## Adding a route

1. Import the destination widget in `lib/app/router.dart`.
2. Add a named route to `LuminhawRouter.routes`, or handle it in
   `onGenerateRoute` when it needs runtime arguments.
3. Open it from a widget with `Navigator.pushNamed`.
4. Pass data through `arguments` and validate its type in the route builder.
5. Use `pushNamedAndRemoveUntil` instead when earlier screens must not remain
   in the Back stack.

Relevant implementation files:

- `lib/main.dart` — app initialization and Supabase auth-event navigation.
- `lib/app/app.dart` — `MaterialApp`, `appNavigatorKey`, and route wiring.
- `lib/app/router.dart` — route names, page builders, and route arguments.
- `lib/features/onboarding/onboarding_flow.dart` — app entry and onboarding.
- `lib/features/home/presentation/app_shell.dart` — five-tab navigation.
- `lib/features/ai_assistant/lumin_assistant_overlay.dart` — floating AI route.
