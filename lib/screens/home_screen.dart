import 'package:flutter/material.dart';
import 'equipment_list_screen.dart';
import 'parts_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _State();
}

class _State extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [EquipmentListScreen(), PartsListScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.precision_manufacturing), label: 'Оборудование'),
          NavigationDestination(icon: Icon(Icons.build), label: 'Детали'),
        ],
      ),
    );
  }
}
