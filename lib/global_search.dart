import 'package:flutter/material.dart';
import '../models.dart';
import '../supabase_client.dart';
import 'equipment_detail_screen.dart';
import 'part_detail_screen.dart';

// Глобальный поиск: машины, детали, артикулы, размеры подшипников.
// Читает напрямую из базы — всегда свежие данные.
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
  List<Equipment> _equipment = [];
  List<Part> _parts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final eq = await supabase.from('equipment').select().order('name');
      final pr = await supabase.from('parts').select().order('name');
      final stock = await fetchStock();
      if (!mounted) return;
      setState(() {
        _equipment =
            (eq as List).map((e) => Equipment.fromMap(e)).toList();
        _parts = (pr as List).map((e) {
          e['stock'] = stock[e['id']] ?? 0;
          return Part.fromMap(e);
        }).toList();
      });
    } catch (_) {}
  }

  List<Equipment> get _machines {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return [];
    return _equipment.where((e) => !e.isArchived && (
        e.name.toLowerCase().contains(q) ||
        (e.model ?? '').toLowerCase().contains(q) ||
        (e.brand ?? '').toLowerCase().contains(q) ||
        (e.serialNumber ?? '').toLowerCase().contains(q) ||
        (e.location ?? '').toLowerCase().contains(q))).toList();
  }

  List<Part> get _foundParts {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return [];
    final size = double.tryParse(q.replaceAll(',', '.'));
    return _parts.where((p) {
      if (p.name.toLowerCase().contains(q) ||
          (p.article ?? '').toLowerCase().contains(q) ||
          (p.bearingType ?? '').toLowerCase().contains(q)) return true;
      if (size != null) {
        for (var v in [p.innerD, p.outerD, p.widthB]) {
          if (v != null && (v - size).abs() < 0.001) return true;
        }
      }
      return false;
    }).toList();
  }

  void _open(Widget screen) {
    Navigator.pop(context);
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final ms = _machines;
    final ps = _foundParts;
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
