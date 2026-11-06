import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../local_db.dart';
import '../models.dart';
import '../supabase_client.dart';
import '../sync_service.dart';

class RepairPartRow {
  String? partId;
  final qty = TextEditingController(text: '1');
}

// Универсальный экран: добавление или редактирование записи о ремонте
class AddRepairScreen extends StatefulWidget {
  final Equipment equipment;
  final Repair? repair; // null = добавление
  const AddRepairScreen({super.key, required this.equipment, this.repair});
  @override
  State<AddRepairScreen> createState() => _State();
}

class _State extends State<AddRepairScreen> {
  final _form = GlobalKey<FormState>();
  late final _description =
      TextEditingController(text: widget.repair?.description ?? '');
  late final _comment =
      TextEditingController(text: widget.repair?.comment ?? '');
  DateTime _date = DateTime.now();
  List<Part> _parts = [];
  Map<String, int> _stock = {};
  Map<String, int> _oldOut = {};
  final List<RepairPartRow> _rows = [RepairPartRow()];
  bool _saving = false;

  Equipment get e => widget.equipment;
  bool get _isEdit => widget.repair != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _date = widget.repair!.date;
    _load();
  }

  Future<void> _load() async {
    // детали и остатки: сначала локально, потом из сети
    setState(() {
      _parts = LocalDb.all(LocalDb.parts).map((x) {
        x['stock'] = LocalDb.stock.get(x['id']) ?? 0;
        return Part.fromMap(x);
      }).toList()..sort((a, b) => a.name.compareTo(b.name));
    });
    try {
      _stock = await fetchStock();
    } catch (_) {
      _stock = {for (var k in LocalDb.stock.keys) k as String: LocalDb.stock.get(k)!};
    }
    if (_isEdit) {
      try {
        final old = await supabase.from('part_movements')
            .select('part_id, qty').eq('repair_id', widget.repair!.id);
        for (var m in old as List) {
          final id = m['part_id'] as String;
          _oldOut[id] = (_oldOut[id] ?? 0) + (m['qty'] as num).toInt();
        }
      } catch (_) {}
      final used = await supabase.from('repair_parts')
          .select().eq('repair_id', widget.repair!.id);
      final usedRows = (used as List).map((x) => x as Map<String, dynamic>).toList();
      if (usedRows.isNotEmpty) {
        _rows.clear();
        for (var x in usedRows) {
          _rows.add(RepairPartRow()
            ..partId = x['part_id'] as String
            ..qty.text = (x['qty'] as num).toString());
        }
      }
    }
    setState(() {});
  }

  int _maxFor(RepairPartRow row) {
    if (row.partId == null) return 0;
    final base = (_stock[row.partId] ?? 0) + (_oldOut[row.partId] ?? 0);
    var usedByOthers = 0;
    for (var other in _rows) {
      if (identical(other, row) || other.partId != row.partId) continue;
      usedByOthers += int.tryParse(other.qty.text) ?? 0;
    }
    return base - usedByOthers;
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  void _offlineNote() => ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Нет сети: сохранено локально, синхронизируется позже')));

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);

    // проверка остатков (по локальным данным, если сети нет)
    final newOut = <String, int>{};
    for (var row in _rows) {
      if (row.partId == null) continue;
      final q = int.tryParse(row.qty.text) ?? 0;
      if (q > 0) newOut[row.partId!] = (newOut[row.partId!] ?? 0) + q;
    }
    final problems = <String>[];
    for (var id in newOut.keys) {
      final available = (_stock[id] ?? 0) + (_oldOut[id] ?? 0);
      if (available - newOut[id]! < 0) {
        var name = id;
        final found = _parts.where((p) => p.id == id);
        if (found.isNotEmpty) name = found.first.name;
        problems.add('$name: нужно ${newOut[id]}, есть $available');
      }
    }
    if (problems.isNotEmpty) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Недостаточно деталей на складе:\n${problems.join('\n')}')));
      return;
    }

    String repairId;
    bool wasOffline;

    if (_isEdit) {
      // проверяем, жива ли сеть
      try {
        await supabase.from('repair_records').select('id').eq('id', widget.repair!.id).single();
      } catch (_) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Нет сети: редактирование ремонта офлайн пока недоступно')));
        return;
      }
      repairId = widget.repair!.id;
      await supabase.from('repair_records').update({
        'date': DateFormat('yyyy-MM-dd').format(_date),
        'description': _description.text.trim(),
        'comment': _comment.text.trim(),
      }).eq('id', repairId);
      await supabase.from('part_movements').delete().eq('repair_id', repairId);
      await supabase.from('repair_parts').delete().eq('repair_id', repairId);
      wasOffline = false;
    } else {
      repairId = const Uuid().v4();
      final repairRow = {
        'id': repairId,
        'equipment_id': e.id,
        'date': DateFormat('yyyy-MM-dd').format(_date),
        'description': _description.text.trim(),
        'comment': _comment.text.trim(),
      };
      wasOffline = await SyncService.saveOrQueue('repair_records', repairRow);
      // локальный кэш записи ремонта (с составом для отображения)
      LocalDb.repairs.put(repairId, {
        ...repairRow,
        'repair_parts': newOut.entries.map((ent) {
          final found = _parts.where((p) => p.id == ent.key);
          final name = found.isEmpty ? '' : found.first.name;
          final unit = found.isEmpty ? 'шт' : found.first.unit;
          return {'qty': ent.value, 'parts': {'name': name, 'unit': unit}};
        }).toList(),
      });
    }

    for (var ent in newOut.entries) {
      final linkRow = {'repair_id': repairId, 'part_id': ent.key, 'qty': ent.value};
      await SyncService.saveOrQueue('repair_parts', linkRow);
      final moveRow = {
        'id': const Uuid().v4(),
        'part_id': ent.key,
        'type': 'out',
        'qty': ent.value,
        'equipment_id': e.id,
        'repair_id': repairId,
        'comment': 'ремонт: ${e.name} ${e.model ?? ''}',
        'created_at': DateTime.now().toIso8601String(),
      };
      bool movedOffline;
      try {
        movedOffline = await SyncService.saveOrQueue('part_movements', moveRow);
      } catch (e) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Списание отклонено: $e')));
        return;
      }
      if (movedOffline || wasOffline) {
        LocalDb.movements.put(moveRow['id'], moveRow);
        LocalDb.stock.put(
            ent.key, (LocalDb.stock.get(ent.key) ?? 0) - ent.value);
      }
    }
    if (wasOffline) _offlineNote();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Ремонт: ${e.name}')),
      body: Form(
        key: _form,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Дата'),
              subtitle: Text(DateFormat('dd.MM.yyyy').format(_date)),
              trailing: const Icon(Icons.calendar_month),
              onTap: _pickDate,
            ),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Описание ремонта *'),
              maxLines: 3,
              validator: (v) => (v == null || v.isEmpty) ? 'Обязательное поле' : null,
            ),
            const SizedBox(height: 16),
            Text('Детали (спишутся со склада)',
                style: Theme.of(context).textTheme.titleMedium),
            ..._rows.asMap().entries.map((entry) {
              final i = entry.key;
              final row = entry.value;
              final max = _maxFor(row);
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: row.partId,
                      decoration: const InputDecoration(labelText: 'Деталь'),
                      items: _parts.map((p) {
                        final avail = (_stock[p.id] ?? 0) + (_oldOut[p.id] ?? 0);
                        return DropdownMenuItem(
                            value: p.id,
                            child: Text('${p.name} (есть $avail)',
                                overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: (v) => setState(() => row.partId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 84,
                    child: TextFormField(
                      controller: row.qty,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Кол-во',
                        helperText: row.partId == null ? null : 'макс. $max',
                      ),
                      validator: (v) {
                        if (row.partId == null) return null;
                        final q = int.tryParse(v ?? '') ?? 0;
                        if (q <= 0) return 'мин. 1';
                        if (q > _maxFor(row)) return 'макс. ${_maxFor(row)}';
                        return null;
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: _rows.length > 1
                          ? () => setState(() => _rows.removeAt(i)) : null,
                    ),
                  ),
                ]),
              );
            }),
            TextButton.icon(
              onPressed: () => setState(() => _rows.add(RepairPartRow())),
              icon: const Icon(Icons.add),
              label: const Text('Добавить деталь'),
            ),
            TextFormField(controller: _comment,
                decoration: const InputDecoration(labelText: 'Комментарий')),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Сохранение…' : 'Сохранить запись'),
            ),
          ],
        ),
      ),
    );
  }
}
