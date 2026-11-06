import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../local_db.dart';
import '../models.dart';
import '../supabase_client.dart';
import '../sync_service.dart';

const bearingTypes = [
  'Шариковый радиальный',
  'Шариковый упорный',
  'Роликовый цилиндрический',
  'Роликовый конический',
  'Роликовый игольчатый',
  'Сферический (самоустанавливающийся)',
  'Шариковый радиально-упорный',
  'Игольчатый',
  'Другой',
];

// Универсальный экран: добавление или редактирование детали (офлайн-ready)
class AddPartScreen extends StatefulWidget {
  final Equipment? equipment; // если открыт из карточки машины — прикрепить после создания
  final Part? part;           // null = добавление
  const AddPartScreen({super.key, this.equipment, this.part});
  @override
  State<AddPartScreen> createState() => _State();
}

class _State extends State<AddPartScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.part?.name ?? '');
  late final _article = TextEditingController(text: widget.part?.article ?? '');
  late final _manufacturer =
      TextEditingController(text: widget.part?.manufacturer ?? '');
  late final _comment = TextEditingController(text: widget.part?.comment ?? '');
  late final _innerD = TextEditingController(
      text: widget.part?.innerD?.toString() ?? '');
  late final _outerD = TextEditingController(
      text: widget.part?.outerD?.toString() ?? '');
  late final _widthB = TextEditingController(
      text: widget.part?.widthB?.toString() ?? '');
  bool _isBearing = false;
  String? _bearingType;
  List<Photo> _existing = [];
  XFile? _newPhoto;
  bool _saving = false;

  bool get _isEdit => widget.part != null;

  @override
  void initState() {
    super.initState();
    _isBearing = widget.part?.isBearing ?? false;
    _bearingType = widget.part?.bearingType;
    _load();
  }

  Future<void> _load() async {
    if (_isEdit) {
      final photos = await supabase.from('photos')
          .select().eq('owner_type', 'part').eq('owner_id', widget.part!.id)
          .order('position');
      setState(() => _existing = (photos as List).map((e) => Photo.fromMap(e)).toList());
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _newPhoto = picked);
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
    setState(() => _saving = true);
    final fields = <String, dynamic>{
      'name': _name.text.trim(),
      'article': _article.text.trim(),
      'manufacturer': _manufacturer.text.trim(),
      'comment': _comment.text.trim(),
      'is_bearing': _isBearing,
      'bearing_type': _isBearing ? _bearingType : null,
      'inner_d': _isBearing ? double.tryParse(_innerD.text) : null,
      'outer_d': _isBearing ? double.tryParse(_outerD.text) : null,
      'width_b': _isBearing ? double.tryParse(_widthB.text) : null,
    };
    String partId;
    bool wasOffline;
    if (_isEdit) {
      partId = widget.part!.id;
      wasOffline = await SyncService.saveOrQueue('parts', fields, updateId: partId);
      if (wasOffline) {
        final local = LocalDb.parts.get(partId);
        if (local != null) local.addAll(fields);
      }
    } else {
      partId = const Uuid().v4();
      wasOffline = await SyncService.saveOrQueue('parts', {...fields, 'id': partId});
      if (wasOffline) {
        LocalDb.parts.put(partId, {...fields, 'id': partId});
        LocalDb.stock.put(partId, 0);
      }
      if (widget.equipment != null) {
        final link = {'equipment_id': widget.equipment!.id, 'part_id': partId};
        if (wasOffline) {
          LocalDb.machineParts
              .put('${widget.equipment!.id}_$partId', link);
        }
        await SyncService.saveOrQueue('machine_parts', link);
      }
    }
    if (wasOffline) _offlineNote();

    if (_newPhoto != null) {
      final path = 'parts/$partId/detail-${_existing.length}.jpg';
      final bytes = await _newPhoto!.readAsBytes();
      final photoRow = {
        'owner_type': 'part',
        'owner_id': partId,
        'kind': 'detail',
        'storage_path': path,
        'position': _existing.length,
      };
      try {
        await supabase.storage.from('photos').uploadBinary(path, bytes);
        await supabase.from('photos').insert(photoRow);
      } catch (_) {
        LocalDb.pendingPhotos.put(path, bytes);
        SyncService.queue('photos', 'insert', photoRow);
      }
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Редактировать деталь' : 'Новая деталь')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.equipment != null)
              Text('Привязка: ${widget.equipment!.name} ${widget.equipment!.model ?? ''}',
                  style: const TextStyle(color: Colors.black54)),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Наименование *'),
              validator: (v) => (v == null || v.isEmpty) ? 'Обязательное поле' : null,
            ),
            TextFormField(controller: _article,
                decoration: const InputDecoration(labelText: 'Артикул / номер по каталогу')),
            TextFormField(controller: _manufacturer,
                decoration: const InputDecoration(labelText: 'Производитель')),
            SwitchListTile(
              title: const Text('Это подшипник'),
              value: _isBearing,
              onChanged: (v) => setState(() => _isBearing = v),
            ),
            if (_isBearing) ...[
              DropdownButtonFormField<String>(
                initialValue: _bearingType,
                decoration: const InputDecoration(labelText: 'Тип подшипника'),
                items: bearingTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => _bearingType = v,
              ),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _innerD,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'd, мм', helperText: 'внутренний диаметр'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _outerD,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'D, мм', helperText: 'наружный диаметр'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _widthB,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'B, мм', helperText: 'ширина'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
            ],
            TextFormField(controller: _comment,
                decoration: const InputDecoration(labelText: 'Комментарий'), maxLines: 2),
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
            OutlinedButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.photo_camera),
              label: Text(_newPhoto == null ? 'Фото детали' : 'Новое фото выбрано ✓'),
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
