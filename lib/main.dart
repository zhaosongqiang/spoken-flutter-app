import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/providers.dart';
import 'router.dart';
import 'ui/design.dart';
import 'ui/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: SpokenApp()));
}

class SpokenApp extends ConsumerStatefulWidget {
  const SpokenApp({super.key});

  @override
  ConsumerState<SpokenApp> createState() => _SpokenAppState();
}

class _SpokenAppState extends ConsumerState<SpokenApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = createAppRouter(onPageChanged: _stopAudio);
  }

  void _stopAudio() {
    if (!ref.exists(audioServiceProvider)) return;
    unawaited(ref.read(audioServiceProvider).stop());
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: '声动AI口语',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        routerConfig: _router,
        builder: (context, child) =>
            BootstrapGate(child: child ?? const SizedBox.shrink()),
      );
}
