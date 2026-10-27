import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/router.dart';
import 'core/session.dart';
import 'core/theme.dart';

class DormyApp extends StatefulWidget {
  const DormyApp({super.key});

  @override
  State<DormyApp> createState() => _DormyAppState();
}

class _DormyAppState extends State<DormyApp> {
  late final GoRouter _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    // Kullanıcı değişince (çıkış / başka hesapla giriş) tüm önbellek sıfırlanır.
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => ProviderScope(
        key: ValueKey(session.userKey),
        child: MaterialApp.router(
          title: 'Dormy',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          locale: const Locale('tr', 'TR'),
          supportedLocales: const [Locale('tr', 'TR')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: _router,
        ),
      ),
    );
  }
}
