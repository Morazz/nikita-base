import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../local_db.dart';
import '../local_sql.dart';
import '../models.dart';
import '../supabase_client.dart';
import '../sync_service.dart';
import 'add_equipment_screen.dart';
import '../photo_viewer.dart';
import 'add_part_screen.dart';
import 'add_repair_screen.dart';
import 'part_detail_screen.dart';

class EquipmentDetailScreen extends StatefulWidget {
  final Equipment equipment;
  final bool embedded;      // true = встроен в мастер-деталь панель
  final VoidCallback? onChanged;
  const EquipmentDetailScreen({super.key, required this.equipment,
      this.embedded = false, this.onChanged});
  @override
  State<EquipmentDetailScreen> createState() => _State();
}

class _State extends State<EquipmentDetailScreen> {
  List<Photo> _photos = [];
  List<Part> _parts = [];
  List<Part> _allParts = [];
  List<Document> _docs = [];
  List<Map<String, dynamic>> _repairs = [];
  bool _loading = true;
  bool _offline = false;

  Equipment get e => widget.equipment;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Part> _linkedPartsLocal() {
    final byId = {for (var p in LocalDb.all(LocalDb.parts)) p['id'] as String: p};
    return LocalDb.all(LocalDb.machineParts)
        .where((m) => m['equipment_id'] == e.id)
        .map((m) => Map<String, dynamic>.from(byId[m['part_id']] ?? {}))
        .where((p) => p.isNotEmpty)
        .map((p) {
          p['stock'] = LocalDb.stock.get(p['id']) ?? 0;
          return Part.fromMap(p);
        }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<void> _load() async {
    // 1. мгновенно из локального кэша
    setState(() {
      _photos = LocalDb.all(LocalDb.photos)
          .where((x) => x['owner_type'] == 'equipment' && x['owner_id'] == e.id)
          .map((x) => Photo.fromMap(x)).toList()
        ..sort((a, b) => a.position - b.position);
      _parts = _linkedPartsLocal();
      _repairs = LocalDb.all(LocalDb.repairs)
          .where((r) => r['equipment_id'] == e.id).toList()
        ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
      _docs = [];
      _allParts = LocalDb.all(LocalDb.parts).map((x) => Part.fromMap(x)).toList();
      _loading = false;
    });
    // 2. свежак из сети
    try {
      final photos = await supabase.from('photos')
          .select().eq('owner_type', 'equipment').eq('owner_id', e.id).order('position');
      final linked = await supabase.from('machine_parts')
          .select('parts(*)').eq('equipment_id', e.id);
      final stock = await fetchStock();
      final repairs = await supabase.from('repair_records')
          .select('*, repair_parts(qty, parts(name, unit))')
          .eq('equipment_id', e.id).order('date', ascending: false);
      final allParts = await supabase.from('parts').select().order('name');
      final docs = await supabase.from('documents')
          .select().eq('equipment_id', e.id).order('name');
      setState(() {
        _offline = false;
        _docs = (docs as List).map((x) => Document.fromMap(x)).toList();
        _photos = (photos as List).map((x) => Photo.fromMap(x)).toList();
        _parts = (linked as List).map((x) {
          final p = Map<String, dynamic>.from(x['parts'] as Map);
          p['stock'] = stock[p['id']] ?? 0;
          return Part.fromMap(p);
        }).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        _repairs = (repairs as List).cast<Map<String, dynamic>>();
        _allParts = (allParts as List).map((x) => Part.fromMap(x)).toList();
      });
    } catch (_) {
      setState(() => _offline = true);
    }
  }

  void _offlineNote() => ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Нет сети: изменено локально, синхронизируется позже')));

  Future<void> _toggleArchive() async {
    final newStatus = e.isArchived ? 'active' : 'archived';
    final wasOffline = await SyncService.saveOrQueue('equipment',
        {'status': newStatus}, updateId: e.id);
    if (wasOffline) {
      LocalDb.equipment.get(e.id)?['status'] = newStatus;
      _offlineNote();
    }
    if (widget.embedded) {
      widget.onChanged?.call();
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить машину?'),
        content: const Text('Удалятся её ремонты и привязки деталей. '
            'Если машина выведена из строя — лучше «В архив».'),
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
    final wasOffline = await SyncService.deleteOrQueue('delete_equipment', e.id);
    if (wasOffline) {
      LocalDb.equipment.delete(e.id);
      _offlineNote();
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addPart() async {
    String q = '';
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final linkedIds = _parts.map((p) => p.id).toSet();
          final available = _allParts.where((p) =>
              !linkedIds.contains(p.id) &&
              (q.isEmpty ||
                  p.name.toLowerCase().contains(q.toLowerCase()) ||
                  (p.article ?? '').toLowerCase().contains(q.toLowerCase()))).toList();
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: SizedBox(
                height: 420,
                child: Column(children: [
                  const ListTile(title: Text('Добавить деталь на машину')),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Поиск по базе деталей'),
                      onChanged: (v) => setSheet(() => q = v),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Создать новую деталь'),
                    onTap: () => Navigator.pop(ctx, 'new'),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: available.isEmpty
                        ? const Center(child: Text('Ничего не найдено'))
                        : ListView.builder(
                            itemCount: available.length,
                            itemBuilder: (_, i) {
                              final p = available[i];
                              return ListTile(
                                dense: true,
                                title: Text(p.name),
                                subtitle: Text('арт. ${p.article ?? '—'}'
                                    '${p.isBearing ? ' · ${p.dims} мм' : ''}'),
                                onTap: () => Navigator.pop(ctx, p.id),
                              );
                            }),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
    if (choice == null) return;
    if (choice == 'new') {
      await Navigator.push(context, MaterialPageRoute(
          builder: (_) => AddPartScreen(equipment: e)));
    } else {
      final link = {'equipment_id': e.id, 'part_id': choice};
      final wasOffline =
          await SyncService.saveOrQueue('machine_parts', link);
      if (wasOffline) {
        LocalDb.machineParts.put('${e.id}_$choice', link);
        _offlineNote();
      }
    }
    _load();
  }

  Future<void> _unlinkPart(Part p) async {
    try {
      await supabase.from('machine_parts').delete()
          .eq('equipment_id', e.id).eq('part_id', p.id);
    } catch (_) {
      // локально убираем связь; полное удаление связки синхронизатор не вернёт,
      // поэтому в offline режиме связь восстановится при следующем pull —
      // приемлемо для редкой операции
      LocalDb.machineParts.delete('${e.id}_${p.id}');
      _offlineNote();
    }
    _load();
  }

  Future<void> _editRepair(Map<String, dynamic> r) async {
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => AddRepairScreen(equipment: e, repair: Repair.fromMap(r))));
    _load();
  }

  Future<void> _deleteRepair(Map<String, dynamic> r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить запись о ремонте?'),
        content: const Text('Движения деталей из этой записи тоже удалятся.'),
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
    final wasOffline = await SyncService.deleteOrQueue('delete_repair', r['id']);
    if (wasOffline) {
      LocalDb.repairs.delete(r['id']);
      _offlineNote();
    }
    _load();
  }

  Future<void> _addDoc() async {
    try {
      final res = await FilePicker.platform.pickFiles();
      final fp = res?.files.single;
      if (fp?.path == null) return;
      final id = const Uuid().v4();
      final safe = fp!.name.replaceAll(RegExp(r'[^\w.\-() ]'), '_');
      final rel = 'docs/${e.id}/$id-$safe';
      final data = await LocalSql.dataDir();
      final dest = File(p.join(data.path, rel));
      await dest.parent.create(recursive: true);
      await File(fp.path!).copy(dest.path);
      await SyncService.saveOrQueue('documents', {
        'id': id,
        'equipment_id': e.id,
        'name': fp.name,
        'storage_path': rel,
        'size': fp.size,
        'created_at': DateTime.now().toIso8601String(),
      });
      _load();
    } catch (err) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось добавить документ: $err')));
    }
  }

  Future<void> _openDoc(Document doc) async {
    final data = await LocalSql.dataDir();
    final path = p.join(data.path, doc.storagePath);
    final res = await OpenFile.open(path);
    if (res.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть: ${res.message}')));
    }
  }

  Future<void> _deleteDoc(Document doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить документ?'),
        content: Text(doc.name),
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
    try {
      await supabase.from('documents').delete().eq('id', doc.id);
    } catch (_) {}
    final data = await LocalSql.dataDir();
    final f = File(p.join(data.path, doc.storagePath));
    if (await f.exists()) await f.delete();
    _load();
  }

  IconData _docIcon(String ext) => switch (ext) {
        'pdf' => Icons.picture_as_pdf,
        'doc' || 'docx' || 'rtf' => Icons.description,
        'xls' || 'xlsx' || 'csv' => Icons.table_chart,
        'png' || 'jpg' || 'jpeg' || 'bmp' => Icons.image,
        'dwg' || 'dxf' => Icons.architecture,
        _ => Icons.insert_drive_file,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(e.name),
        actions: [
          if (_offline)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.cloud_off, size: 18, color: Colors.orange),
            ),
          if (!e.isArchived)
            IconButton(icon: const Icon(Icons.edit), onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AddEquipmentScreen(equipment: e)));
              _load();
            }),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'archive') _toggleArchive();
              if (v == 'delete') _delete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'archive',
                  child: Text(e.isArchived ? 'Вернуть из архива' : 'В архив')),
              const PopupMenuItem(value: 'delete', child: Text('Удалить')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_photos.isNotEmpty)
                  SizedBox(
                    height: 140,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _photos.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () =>
                            showPhotoViewer(context, _photos, i),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LocalImage(_photos[i].storagePath,
                              width: 140, height: 140),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                _spec('Марка, модель',
                    [e.brand, e.model].whereType<String>().join(' ').isEmpty
                        ? '—'
                        : [e.brand, e.model].whereType<String>().join(' ')),
                _spec('Зав. №', e.serialNumber ?? '—'),
                _spec('Производитель', e.manufacturer ?? '—'),
                _spec('Год выпуска', e.year?.toString() ?? '—'),
                _spec('Расположение', e.location ?? '—'),
                if (e.comment != null && e.comment!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Комментарий', style: Theme.of(context).textTheme.labelSmall),
                  Text(e.comment!),
                ],
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addPart,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Деталь'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(context, MaterialPageRoute(
                            builder: (_) => AddRepairScreen(equipment: e)));
                        _load();
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Ремонт'),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _addDoc,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: Text('Документ · ${_docs.length}'),
                  ),
                ),
                if (_docs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Документы · ${_docs.length}',
                      style: Theme.of(context).textTheme.titleMedium),
                  ..._docs.map((doc) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(_docIcon(doc.ext), size: 20),
                        title: Text(doc.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _deleteDoc(doc),
                        ),
                        onTap: () => _openDoc(doc),
                      )),
                ],
                const SizedBox(height: 8),
                Text('Детали · ${_parts.length}',
                    style: Theme.of(context).textTheme.titleMedium),
                ..._parts.map((p) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.name),
                      subtitle: Text('арт. ${p.article ?? '—'}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('${p.stock} ${p.unit}'),
                        IconButton(
                          icon: const Icon(Icons.link_off, size: 18),
                          tooltip: 'Убрать с этой машины (деталь останется в базе)',
                          onPressed: () => _unlinkPart(p),
                        ),
                      ]),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(
                            builder: (_) => PartDetailScreen(part: p)));
                        _load();
                      },
                    )),
                const SizedBox(height: 16),
                Text('История ремонтов · ${_repairs.length}',
                    style: Theme.of(context).textTheme.titleMedium),
                ..._repairs.map((r) {
                  final parts = (r['repair_parts'] as List? ?? []);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${(r['date'] as String).substring(0, 10)} — ${r['description']}',
                                  style: const TextStyle(fontWeight: FontWeight.w500)),
                              if (parts.isNotEmpty)
                                Text(parts.map((p) {
                                  final part = p['parts'] as Map<String, dynamic>;
                                  return '${part['name']} × ${p['qty']}';
                                }).join(' · '),
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => _editRepair(r),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () => _deleteRepair(r),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
    );
  }

  Widget _spec(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            Flexible(child: Text(value, textAlign: TextAlign.right)),
          ],
        ),
      );
}
