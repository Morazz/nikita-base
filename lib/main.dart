import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_db.dart';
import 'local_sql.dart';
import 'screens/home_screen.dart';
import 'sync_service.dart';

final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);
final navigatorKey = GlobalKey<NavigatorState>();

// Вместо «серого экрана» показываем диалог с текстом ошибки.
// Полный стек пишется в Документы\oborudovanie_errors.log
void showAppError(Object error, [StackTrace? stack]) async {
  try {
    final data = await LocalSql.dataDir();
    final f = File('${data.path}/oborudovanie_errors.log');
    await f.writeAsString(
        '${DateTime.now()}\n$error\n${stack ?? StackTrace.current}\n\n',
        mode: FileMode.append);
  } catch (_) {}
  final ctx = navigatorKey.currentContext;
  if (ctx == null || !ctx.mounted) return;
  final msg = error.toString();
  showDialog(
    context: ctx,
    builder: (dctx) => AlertDialog(
      title: const Text('Ошибка'),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min, children: [
          Text(msg.length > 400 ? '${msg.substring(0, 400)}…' : msg),
          const SizedBox(height: 8),
          Text('Подробности: Документы\\oborudovanie_errors.log',
              style: Theme.of(ctx).textTheme.bodySmall),
        ]),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('Понятно')),
      ],
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (!kDebugMode) showAppError(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (!kDebugMode) showAppError(error, stack);
    return true;
  };
  final dataDir = await LocalSql.dataDir();
  await LocalDb.init(path: dataDir.path);
  final prefs = await SharedPreferences.getInstance();
  themeModeNotifier.value = switch (prefs.getString('theme')) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
  runApp(const OborudovanieApp());
  SyncService.syncAll();
}

void toggleTheme() async {
  final isDark = themeModeNotifier.value == ThemeMode.dark ||
      (themeModeNotifier.value == ThemeMode.system &&
          WidgetsBinding.instance.platformDispatcher.platformBrightness ==
              Brightness.dark);
  themeModeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
      'theme', themeModeNotifier.value == ThemeMode.dark ? 'dark' : 'light');
}

class OborudovanieApp extends StatelessWidget {
  const OborudovanieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) => MaterialApp(
        title: 'Оборудование',
        navigatorKey: navigatorKey,
        themeMode: mode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.blueGrey, brightness: Brightness.dark),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
