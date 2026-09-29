import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/providers/app_provider.dart';
import 'router.dart';
import 'theme.dart';

class ELearningApp extends ConsumerStatefulWidget {
  const ELearningApp({super.key});
  @override
  ConsumerState<ELearningApp> createState() => _ELearningAppState();
}

class _ELearningAppState extends ConsumerState<ELearningApp>
    with WidgetsBindingObserver {
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
      unawaited(ref.read(appProvider).refresh().catchError((Object _) {}));
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'E-Learning',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    locale: const Locale('id', 'ID'),
    supportedLocales: const [Locale('id', 'ID'), Locale('en', 'US')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    routerConfig: ref.watch(routerProvider),
  );
}
