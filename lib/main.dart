import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'app/app.dart';
import 'app/theme.dart';
import 'core/config/app_config.dart';
import 'shared/providers/app_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Bootstrap());
}

class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});
  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  late Future<AppStore> future;
  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<AppStore> _load() async {
    AppConfig.validate();
    await initializeDateFormatting('id_ID');
    final s = makeStore();
    try {
      await s.initialize();
      return s;
    } catch (_) {
      s.dispose();
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppStore>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return ProviderScope(
          overrides: [appProvider.overrideWith((ref) => snapshot.data!)],
          child: const ELearningApp(),
        );
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: snapshot.hasError
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.school_outlined, size: 58),
                        const SizedBox(height: 20),
                        const Text(
                          'Aplikasi belum dapat dimulai.',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          snapshot.error is StateError
                              ? (snapshot.error as StateError).message
                              : 'Periksa koneksi lalu coba lagi.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: () => setState(() => future = _load()),
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
        ),
      );
    },
  );
}
