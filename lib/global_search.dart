import 'package:flutter/material.dart';
import 'local_db.dart';
import 'models.dart';
import 'screens/equipment_detail_screen.dart';
import 'screens/part_detail_screen.dart';

// Глобальный поиск: машины, детали, артикулы, размеры подшипников
Future<void> showGlobalSearch(BuildContext context) async {
  await showDialog(context: context, builder: (_) => const GlobalSearchDialog());
}

class GlobalSearchDialog extends StatefulWidget {
  const GlobalSearchDialog({super.key});
  @override
  State<GlobalSearchDialog> createState() => _State();
}

class _State extends State<GlobalSearchDialog> {
  String _q = '';

  List<Equipment> get _machines {
    final all = LocalDb.all(LocalDb.equipment);
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return [];
    return all.where((e) =>
        (e['name'] ?? '').toString().toLowerCase().contains(q) ||
        (e['model'] ?? '').toString().toLowerCase().contains(q) ||
        (e['serial_number'] ?? '').toString().toLowerCase().contains(q) ||
        (e['location'] ?? '').toString().toLowerCase().contains(q)).map((e) =>
        Equipment.fromMap(e)).toList();
  }

  List<Part> get _parts {
    final all = LocalDb.all(LocalDb.parts);
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return [];
    final size = double.tryParse(q.replaceAll(',', '.'));
    return all.where((e) {
      if ((e['name'] ?? '').toString().toLowerCase().contains(q) ||
          (e['article'] ?? '').toString().toLowerCase().contains(q) ||
          (e['bearing_type'] ?? '').toString().toLowerCase().contains(q)) {
        return true;
      }
      if (size != null) {
        for (var k in ['inner_d', 'outer_d', 'width_b']) {
          final v = e[k];
          if (v != null && ((v as num) - size).abs() < 0.001) return true;
        }
      }
      return false;
    }).map((e) {
      e['stock'] = LocalDb.stock.get(e['id']) ?? 0;
      return Part.fromMap(e);
    }).toList();
  }

  void _open(Widget screen) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final ms = _machines;
    final ps = _parts;
    return Dialog(
      child: SizedBox(
        width: 620, height: 480,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Поиск: машина, модель, зав. №, артикул, размер…',
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: _q.trim().isEmpty
                ? const Center(
                    child: Text('Введите запрос — ищу по всей базе',
                        style: TextStyle(color: Colors.grey)))
                : ListView(children: [
                    if (ms.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text('Оборудование',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      ...ms.map((e) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.precision_manufacturing),
                            title: Text(e.name),
                            subtitle: Text(
                                '${[e.brand, e.model].whereType<String>().join(' ')} · зав. № ${e.serialNumber ?? '—'}'),
                            onTap: () => _open(EquipmentDetailScreen(equipment: e)),
                          )),
                    ],
                    if (ps.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Text('Детали',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      ...ps.map((p) => ListTile(
                            dense: true,
                            leading: const Icon(Icons.settings),
                            title: Text(p.name),
                            subtitle: Text(p.isBearing
                                ? '${p.bearingType ?? ''} · ${p.dims} мм'
                                : 'арт. ${p.article ?? '—'}'),
                            trailing: Text('${p.stock} ${p.unit}'),
                            onTap: () => _open(PartDetailScreen(part: p)),
                          )),
                    ],
                    if (ms.isEmpty && ps.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: Text('Ничего не найдено')),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}
