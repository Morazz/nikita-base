import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../backup.dart';
import '../global_search.dart';
import '../main.dart';
import 'equipment_list_screen.dart';
import 'parts_list_screen.dart';
import '../sync_service.dart';

// Десктопная оболочка: навигация слева, контент справа
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _State();
}

class _State extends State<HomeScreen> {
  int _tab = 0;

  void _openSearch() => showGlobalSearch(context);

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _openSearch,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(children: [
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: (i) {
                setState(() => _tab = i);
                SyncService.syncAll();
              },
              labelType: NavigationRailLabelType.all,
              trailing: Column(children: [
                const SizedBox(height: 16),
                IconButton(
                  tooltip: 'Поиск по всей базе (Ctrl+K)',
                  icon: const Icon(Icons.search),
                  onPressed: _openSearch,
                ),
                const SizedBox(height: 4),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: themeModeNotifier,
                  builder: (context, mode, _) {
                    final isDark = mode == ThemeMode.dark;
                    return IconButton(
                      tooltip: isDark ? 'Светлая тема' : 'Тёмная тема',
                      icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                      onPressed: toggleTheme,
                    );
                  },
                ),
                const SizedBox(height: 12),
                IconButton(
                  tooltip: 'Экспорт базы (zip)',
                  icon: const Icon(Icons.upload),
                  onPressed: () async {
                    try {
                      final path = await BackupService.exportBackup(context);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(path == null
                                ? 'Экспорт отменён'
                                : 'Копия сохранена: $path')));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Ошибка экспорта: $e')));
                      }
                    }
                  },
                ),
                IconButton(
                  tooltip: 'Импорт базы из zip',
                  icon: const Icon(Icons.download),
                  onPressed: () async {
                    bool ok = false;
                    try {
                      ok = await BackupService.importBackup();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Ошибка импорта: $e')));
                      }
                      return;
                    }
                    if (!context.mounted) return;
                    if (ok) {
                      SyncService.syncAll();
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('База импортирована'),
                          content: const Text(
                              'Данные восстановлены из копии. Перезапустите программу, чтобы всё обновилось.'),
                          actions: [
                            FilledButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Понятно')),
                          ],
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Импорт отменён или файл не является копией базы')));
                    }
                  },
                ),
              ]),
              destinations: const [
                NavigationRailDestination(
                    icon: Icon(Icons.precision_manufacturing),
                    label: Text('Оборудование')),
                NavigationRailDestination(
                    icon: Icon(Icons.build), label: Text('Детали')),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [EquipmentListScreen(), PartsListScreen()],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
