import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_db.dart';
import 'screens/home_screen.dart';
import 'sync_service.dart';

final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDb.init();
  final prefs = await SharedPreferences.getInstance();
  themeModeNotifier.value =
      switch (prefs.getString('theme')) {
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
