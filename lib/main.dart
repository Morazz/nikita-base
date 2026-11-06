import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/home_screen.dart';
import 'supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const OborudovanieApp());
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
