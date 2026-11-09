import 'package:flutter/material.dart';
import 'package:luminhaw/app/router.dart';
import 'package:luminhaw/app/theme.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

class LuminhawApp extends StatelessWidget {
  const LuminhawApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Luminhaw',
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: LuminhawTheme.light,
      builder: (context, child) => ScrollConfiguration(
        behavior: const _AppScrollBehavior(),
        child: child ?? const SizedBox.shrink(),
      ),
      initialRoute: LuminhawRouter.initialRoute,
      routes: LuminhawRouter.routes,
      onGenerateRoute: LuminhawRouter.onGenerateRoute,
    );
  }
}

class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
