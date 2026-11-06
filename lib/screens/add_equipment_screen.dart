import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../local_db.dart';
import '../models.dart';
import '../supabase_client.dart';
import '../sync_service.dart';

// Универсальный экран: добавление или редактирование оборудования (офлайн-ready)
class AddEquipmentScreen extends StatefulWidget {
  final Equipment? equipment; // null = добавление
  const AddEquipmentScreen({super.key, this.equipment});
  @override
  State<AddEquipmentScreen> createState() => _State();
}

class _State extends State<AddEquipmentScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.equipment?.name ?? '');
  late final _brand = TextEditingController(text: widget.equipment?.brand ?? '');
  late final _model = TextEditingController(text: widget.equipment?.model ?? '');
  late final _serial = TextEditingController(text: widget.equipment?.serialNumber ?? '');
  late final _location = TextEditingController(text: widget.equipment?.location ?? '');
  late final _comment = TextEditingController(text: widget.equipment?.comment ?? '');
  List<Site> _sites = [];
  String? _siteId;
  List<Photo> _existing = [];
  final List<XFile> _newPhotos = [];
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.equipment != null;

  @override
  void initState() {
    super.initState();
    _siteId = widget.equipment?.siteId;
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await supabase.from('sites').select().order('name');
      setState(() => _sites = (rows as List).map((e) => Site.fromMap(e)).toList());
      if (_isEdit) {
        final photos = await supabase.from('photos')
            .select().eq('owner_type', 'equipment').eq('owner_id', widget.equipment!.id)
            .order('position');
        setState(() => _existing = (photos as List).map((e) => Photo.fromMap(e)).toList());
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pickPhotos() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isNotEmpty) setState(() => _newPhotos.addAll(picked));
  }

  Future<void> _deleteExistingPhoto(Photo photo) async {
    try {
      await supabase.from('photos').delete().eq('id', photo.id);
      await supabase.storage.from('photos').remove([photo.storagePath]);
    } catch (_) {}
    setState(() => _existing.remove(photo));
  }

  void _offlineNote() => ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Нет сети: сохранено локально, синхронизируется позже')));

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_siteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Выберите площадку')));
      return;
    }
    setState(() => _saving = true);
    final fields = <String, dynamic>{
      'site_id': _siteId,
      'name': _name.text.trim(),
      'brand': _brand.text.trim(),
      'model': _model.text.trim(),
      'serial_number': _serial.text.trim(),
      'location': _location.text.trim(),
      'comment': _comment.text.trim(),
    };
    String equipmentId;
    bool wasOffline;
    if (_isEdit) {
      equipmentId = widget.equipment!.id;
      wasOffline = await SyncService.saveOrQueue('equipment', fields, updateId: equipmentId);
      if (wasOffline) {
        final local = LocalDb.equipment.get(equipmentId);
        if (local != null) local.addAll(fields);
      }
    } else {
      equipmentId = const Uuid().v4();
      wasOffline = await SyncService.saveOrQueue('equipment', {...fields, 'id': equipmentId});
      if (wasOffline) {
        LocalDb.equipment.put(equipmentId, {
          ...fields, 'id': equipmentId, 'status': 'active',
        });
      }
    }
    if (wasOffline) _offlineNote();

    final base = _existing.length;
    for (var i = 0; i < _newPhotos.length; i++) {
      final bytes = await _newPhotos[i].readAsBytes();
      final pos = base + i;
      final kind = pos == 0 ? 'general' : (pos == 1 ? 'nameplate' : 'extra');
      final path = 'equipment/$equipmentId/$kind-$pos.jpg';
      final photoRow = {
        'owner_type': 'equipment',
        'owner_id': equipmentId,
        'kind': kind,
        'storage_path': path,
        'position': pos,
      };
      try {
        await supabase.storage.from('photos').uploadBinary(path, bytes);
        await supabase.from('photos').insert(photoRow);
      } catch (_) {
        // офлайн: фото ждёт выгрузки, запись о фото уйдёт в очередь
        LocalDb.pendingPhotos.put(path, bytes);
        SyncService.queue('photos', 'insert', photoRow);
      }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Редактировать' : 'Новое оборудование')),
      body: _error != null && _sites.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Нет сети и локальных данных площадок', textAlign: TextAlign.center),
                const SizedBox(height: 8),
                FilledButton(onPressed: _load, child: const Text('Повторить')),
              ]),
            )
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _siteId,
                    decoration: const InputDecoration(labelText: 'Площадка'),
                    items: _sites
                        .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                        .toList(),
                    onChanged: (v) => _siteId = v,
                  ),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Наименование *'),
                    validator: (v) => (v == null || v.isEmpty) ? 'Обязательное поле' : null,
                  ),
                  TextFormField(controller: _brand, decoration: const InputDecoration(labelText: 'Марка')),
                  TextFormField(controller: _model, decoration: const InputDecoration(labelText: 'Модель')),
                  TextFormField(controller: _serial, decoration: const InputDecoration(labelText: 'Заводской номер')),
                  TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'Расположение')),
                  TextFormField(
                    controller: _comment,
                    decoration: const InputDecoration(labelText: 'Комментарий / описание'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  ..._existing.map((ph) => Row(children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: LocalImage(ph.storagePath,
                                height: 72, width: double.infinity),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteExistingPhoto(ph),
                        ),
                      ])),
                  ..._newPhotos.asMap().entries.map((e) => Row(children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('Новое фото ${e.key + 1}',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _newPhotos.removeAt(e.key)),
                        ),
                      ])),
                  OutlinedButton.icon(
                    onPressed: _pickPhotos,
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Добавить фото (первое — общий вид, второе — шильд)'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Сохранение…' : 'Сохранить'),
                  ),
                ],
              ),
            ),
    );
  }
}
