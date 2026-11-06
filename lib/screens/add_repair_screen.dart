import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../supabase_client.dart';

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
  Map<String, int> _stock = {};   // остатки на складе
  Map<String, int> _oldOut = {};  // движения этого ремонта (при редактировании)
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
    final rows = await supabase.from('parts').select().order('name');
    _stock = await fetchStock();
    if (_isEdit) {
      final old = await supabase.from('part_movements')
          .select('part_id, qty').eq('repair_id', widget.repair!.id);
      for (var m in old as List) {
        final id = m['part_id'] as String;
        _oldOut[id] = (_oldOut[id] ?? 0) + (m['qty'] as num).toInt();
      }
    }
    setState(() => _parts = (rows as List).map((x) => Part.fromMap(x)).toList());
  }

  // Сколько можно взять этой деталью в данной строке с учётом других строк
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

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);

    // --- финальная проверка (подстраховка поверх полей) ---
    final problems = <String>[];
    final newOut = <String, int>{};
    for (var row in _rows) {
      if (row.partId == null) continue;
      final q = int.tryParse(row.qty.text) ?? 0;
      if (q > 0) newOut[row.partId!] = (newOut[row.partId!] ?? 0) + q;
    }
    for (var id in newOut.keys) {
      final available = (_stock[id] ?? 0) + (_oldOut[id] ?? 0);
      if (available - newOut[id]! < 0) {
        var name = id;
        final found = _parts.where((p) => p.id == id);
        if (found.isNotEmpty) name = found.first.name;
        problems.add(name);
      }
    }
    if (problems.isNotEmpty) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Проверьте количество: недостаточно деталей на складе')));
      return;
    }
    // --- конец проверки ---

    String repairId;
    if (_isEdit) {
      repairId = widget.repair!.id;
      await supabase.from('repair_records').update({
        'date': DateFormat('yyyy-MM-dd').format(_date),
        'description': _description.text.trim(),
        'comment': _comment.text.trim(),
      }).eq('id', repairId);
      await supabase.from('part_movements').delete().eq('repair_id', repairId);
      await supabase.from('repair_parts').delete().eq('repair_id', repairId);
    } else {
      final repair = await supabase.from('repair_records').insert({
        'equipment_id': e.id,
        'date': DateFormat('yyyy-MM-dd').format(_date),
        'description': _description.text.trim(),
        'comment': _comment.text.trim(),
      }).select().single();
      repairId = repair['id'] as String;
    }

    for (var row in _rows) {
      if (row.partId == null) continue;
      final qty = int.tryParse(row.qty.text) ?? 0;
      if (qty <= 0) continue;
      await supabase.from('repair_parts').insert({
        'repair_id': repairId, 'part_id': row.partId, 'qty': qty,
      });
      await supabase.from('part_movements').insert({
        'part_id': row.partId,
        'type': 'out',
        'qty': qty,
        'equipment_id': e.id,
        'repair_id': repairId,
        'comment': 'ремонт: ${e.name} ${e.model ?? ''}',
      });
    }
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
                        final avail =
                            (_stock[p.id] ?? 0) + (_oldOut[p.id] ?? 0);
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
                        if (q > _maxFor(row)) return "макс. ${_maxFor(row)}";
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
