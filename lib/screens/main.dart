import 'package:flutter/material.dart';
import 'local_db.dart';
import 'screens/home_screen.dart';
import 'sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDb.init();
  runApp(const OborudovanieApp());
  SyncService.syncAll();
}

class OborudovanieApp extends StatelessWidget {
  const OborudovanieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Оборудование',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
