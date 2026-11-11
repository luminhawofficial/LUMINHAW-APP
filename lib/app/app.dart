import 'package:flutter/material.dart';
import 'package:luminhaw/app/router.dart';
import 'package:luminhaw/app/theme.dart';
import 'package:luminhaw/core/services/plan_entitlement_store.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

class LuminhawApp extends StatefulWidget {
  const LuminhawApp({
    super.key,
    this.initialRoute = LuminhawRouter.initialRoute,
  });

  final String initialRoute;

  @override
  State<LuminhawApp> createState() => _LuminhawAppState();
}

class _LuminhawAppState extends State<LuminhawApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshEntitlement();
    }
  }

  Future<void> _refreshEntitlement() async {
    try {
      await PlanEntitlementStore.instance.refreshFromServer();
    } catch (error) {
      debugPrint('Subscription refresh on resume failed: $error');
    }
  }

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
      initialRoute: widget.initialRoute,
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
