import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';
import 'core/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR');

  if (!Env.isConfigured) {
    runApp(_MissingConfigApp(Env.configError!));
    return;
  }

  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseKey);
  session.start();
  runApp(const DormyApp());
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp(this.problem);

  final String problem;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Supabase yapılandırması hatalı.\n\n$problem\n\n'
              'Uygulamayı şu şekilde çalıştırın:\n'
              'flutter run --dart-define-from-file=env.json\n\n'
              'Ayrıntılar için README.md dosyasına bakın.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
