import 'package:flutter/material.dart';
import '../local_db.dart';
import '../models.dart';
import '../supabase_client.dart';
import '../sync_service.dart';
import 'add_part_screen.dart';

class PartDetailScreen extends StatefulWidget {
  final Part part;
  final bool embedded;
  final VoidCallback? onChanged;
  const PartDetailScreen({super.key, required this.part,
      this.embedded = false, this.onChanged});
  @override
  State<PartDetailScreen> createState() => _State();
}

class _State extends State<PartDetailScreen> {
  List<Photo> _photos = [];
  List<PartMovement> _movements = [];
  List<String> _machines = [];
  int _stock = 0;
  bool _loading = true;
  bool _offline = false;

  Part get p => widget.part;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 1. мгновенно из локального кэша
    setState(() {
      _photos = LocalDb.all(LocalDb.photos)
          .where((x) => x['owner_type'] == 'part' && x['owner_id'] == p.id)
          .map((x) => Photo.fromMap(x)).toList()
        ..sort((a, b) => a.position - b.position);
      _movements = LocalDb.all(LocalDb.movements)
          .where((x) => x['part_id'] == p.id)
          .map((x) => PartMovement.fromMap(x)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _stock = LocalDb.stock.get(p.id) ?? 0;
      final byEq = {for (var m in LocalDb.all(LocalDb.equipment)) m['id'] as String: m};
      _machines = LocalDb.all(LocalDb.machineParts)
          .where((m) => m['part_id'] == p.id)
          .map((m) {
            final eq = byEq[m['equipment_id']] ?? {};
            return '${eq['name'] ?? ''} ${eq['model'] ?? ''}'.trim();
          }).toList();
      _loading = false;
    });
    // 2. свежак из сети
    try {
      final photos = await supabase.from('photos')
          .select().eq('owner_type', 'part').eq('owner_id', p.id).order('position');
      final movements = await supabase.from('part_movements')
          .select().eq('part_id', p.id).order('created_at', ascending: false);
      final linked = await supabase.from('machine_parts')
          .select('equipment(name, model)').eq('part_id', p.id);
      final stock = await supabase.from('part_stock')
          .select().eq('part_id', p.id).maybeSingle();
      setState(() {
        _offline = false;
        _photos = (photos as List).map((e) => Photo.fromMap(e)).toList();
        _movements = (movements as List).map((e) => PartMovement.fromMap(e)).toList();
        _machines = (linked as List).map((x) {
          final eq = x['equipment'] as Map<String, dynamic>;
          return '${eq['name']} ${eq['model'] ?? ''}'.trim();
        }).toList();
        _stock = stock != null ? (stock['stock'] as num).toInt() : 0;
      });
    } catch (_) {
      setState(() => _offline = true);
    }
  }

  void _offlineNote() => ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Нет сети: изменено локально, синхронизируется позже')));

  Future<void> _addMovement(String type, String title) async {
    final qty = TextEditingController(text: '1');
    final comment = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: qty,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Количество'),
          ),
          TextField(
            controller: comment,
            decoration: const InputDecoration(labelText: 'Комментарий'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (ok != true) return;
    final q = int.tryParse(qty.text) ?? 0;
    if (q <= 0) return;
    if ((type == 'out' || type == 'writeoff') && q > _stock) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('На складе только $_stock ${p.unit} — операция отменена')));
      return;
    }
    final data = {
      'id': DateTime.now().microsecondsSinceEpoch.toString(), // временный локальный id
      'part_id': p.id,
      'type': type,
      'qty': q,
      'comment': comment.text.trim(),
      'created_at': DateTime.now().toIso8601String(),
    };
    final wasOffline = await SyncService.saveOrQueue('part_movements', data);
    if (wasOffline) {
      // обновляем локальное состояние сразу
      LocalDb.movements.put(data['id'], data);
      final delta = type == 'in' ? q : -q;
      LocalDb.stock.put(p.id, (LocalDb.stock.get(p.id) ?? _stock) + delta);
      _offlineNote();
    }
    _load();
    widget.onChanged?.call();
  }

  Future<void> _edit() async {
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => AddPartScreen(part: p)));
    _load();
    widget.onChanged?.call();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить деталь?'),
        content: const Text('Удалятся также её фото и история движения.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    final wasOffline = await SyncService.deleteOrQueue('delete_part', p.id);
    if (wasOffline) {
      LocalDb.parts.delete(p.id);
      _offlineNote();
    }
    if (widget.embedded) {
      widget.onChanged?.call();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  Widget _dim(String label, double? v) => Column(children: [
        Text(label, style: const TextStyle(color: Colors.black54)),
        Text(v == null ? '—' : v.toStringAsFixed(
            v == v.roundToDouble() ? 0 : 1),
            style: Theme.of(context).textTheme.titleLarge),
        const Text('мм', style: TextStyle(color: Colors.black38, fontSize: 12)),
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          if (_offline)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.cloud_off, size: 18, color: Colors.orange),
            ),
          IconButton(icon: const Icon(Icons.edit), onPressed: _edit),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_photos.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LocalImage(_photos.first.storagePath,
                        height: 160, width: double.infinity),
                  ),
                if (p.isBearing) ...[
                  const SizedBox(height: 4),
                  Chip(label: Text(p.bearingType ?? 'подшипник')),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _dim('d', p.innerD),
                    _dim('D', p.outerD),
                    _dim('B', p.widthB),
                  ]),
                ],
                const SizedBox(height: 12),
                Center(
                  child: Column(children: [
                    Text('$_stock',
                        style: Theme.of(context).textTheme.displaySmall),
                    Text('${p.unit} на складе',
                        style: const TextStyle(color: Colors.black54)),
                  ]),
                ),
                if (_machines.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Числится на: ${_machines.join(' · ')}',
                      style: const TextStyle(color: Colors.black54)),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: FilledButton(
                      onPressed: () => _addMovement('in', 'Приход'),
                      child: const Text('Приход'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton(
                      onPressed: () => _addMovement('out', 'Расход'),
                      child: const Text('Расход'))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton(
                      onPressed: () => _addMovement('writeoff', 'Списание'),
                      child: const Text('Списание'))),
                ]),
                const SizedBox(height: 16),
                Text('Движение', style: Theme.of(context).textTheme.titleMedium),
                ..._movements.map((m) {
                  final label = switch (m.type) {
                    'in' => 'Приход',
                    'out' => 'Расход',
                    _ => 'Списание',
                  };
                  final color = switch (m.type) {
                    'in' => Colors.green,
                    'out' => Colors.black87,
                    _ => Colors.red,
                  };
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Text(label,
                        style: TextStyle(color: color, fontWeight: FontWeight.w500)),
                    title: Text(m.comment ?? '', maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    trailing: Text('${m.qty} ${p.unit}'),
                  );
                }),
              ],
            ),
    );
  }
}
