import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_db.dart';
import 'screens/home_screen.dart';
import 'sync_service.dart';

final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);
final navigatorKey = GlobalKey<NavigatorState>();

// Вместо «серого экрана» показываем диалог с текстом ошибки
void showAppError(Object error) {
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return;
  final msg = error.toString();
  showDialog(
    context: ctx,
    builder: (dctx) => AlertDialog(
      title: const Text('Ошибка'),
      content: SingleChildScrollView(
          child: Text(msg.length > 600 ? msg.substring(0, 600) + '…' : msg)),
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
    if (!kDebugMode) showAppError(details.exception);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (!kDebugMode) showAppError(error);
    return true;
  };
  await LocalDb.init();
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
