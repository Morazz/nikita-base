import 'package:flutter/material.dart';
import '../local_db.dart';
import '../models.dart';
import '../supabase_client.dart';
import 'add_equipment_screen.dart';
import 'equipment_detail_screen.dart';

// Десктопная раскладка: слева список, справа карточка выбранной машины
class EquipmentListScreen extends StatefulWidget {
  const EquipmentListScreen({super.key});
  @override
  State<EquipmentListScreen> createState() => _State();
}

class _State extends State<EquipmentListScreen> {
  List<Site> _sites = [];
  List<Equipment> _equipment = [];
  String _site = 'Все'; // 'Все' | 'Архив' | id площадки
  Equipment? _selected;
  bool _loading = true;
  String? _error;

  static const double _kWideBreakpoint = 1000;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 1. мгновенно из локального кэша
    setState(() {
      _sites = LocalDb.all(LocalDb.sites).map((e) => Site.fromMap(e)).toList();
      _equipment =
          LocalDb.all(LocalDb.equipment).map((e) => Equipment.fromMap(e)).toList();
      _loading = false;
    });
    // 2. свежие данные из сети/локальной базы
    try {
      final sites = await supabase.from('sites').select();
      final eq = await supabase.from('equipment').select().order('name');
      setState(() {
        _sites = (sites as List).map((e) => Site.fromMap(e)).toList();
        _equipment = (eq as List).map((e) => Equipment.fromMap(e)).toList();
        _error = null;
      });
    } catch (e) {
      if (_equipment.isEmpty) {
        setState(() => _error = 'Нет данных: $e');
      }
    }
  }

  List<Equipment> get _filtered {
    if (_site == 'Архив') return _equipment.where((e) => e.isArchived).toList();
    return _equipment
        .where((e) => !e.isArchived && (_site == 'Все' || e.siteId == _site))
        .toList();
  }

  void _onDetailChanged() {
    // карточку убираем сразу — не даём ей перестраиваться на удалённой машине
    setState(() => _selected = null);
    _load();
  }

  void _openDetail(Equipment e, bool wide) {
    if (wide) {
      setState(() => _selected = e);
    } else {
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => EquipmentDetailScreen(equipment: e))).then((_) => _load());
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= _kWideBreakpoint;
    final list = _buildList(wide);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Добавить оборудование',
          icon: const Icon(Icons.add),
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(
                builder: (_) => const AddEquipmentScreen()));
            _load();
          },
        ),
        title: const Text('Оборудование'),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_equipment',
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AddEquipmentScreen()));
          _load();
        },
        child: const Icon(Icons.add),
      ),
      body: _error != null && _equipment.isEmpty
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Ошибка загрузки: $_error', textAlign: TextAlign.center),
                const SizedBox(height: 8),
                FilledButton(onPressed: _load, child: const Text('Повторить')),
              ]),
            )
          : wide
              ? Row(children: [
                  SizedBox(width: 500, child: list),
                  const VerticalDivider(width: 1),
                  Expanded(child: _buildDetailPanel()),
                ])
              : list,
    );
  }

  Widget _buildDetailPanel() {
    final sel = _selected;
    if (sel == null) {
      return Center(
          child: Text('Выберите машину в списке слева',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)));
    }
    final fresh = _equipment.firstWhere((x) => x.id == sel.id, orElse: () => sel);
    return EquipmentDetailScreen(
      key: ValueKey('eq-${fresh.id}'),
      equipment: fresh,
      embedded: true,
      onChanged: _onDetailChanged,
    );
  }

  Widget _buildList(bool wide) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _chip('Все'),
              ..._sites.map((s) => _chip(s.name, id: s.id)),
              _chip('Архив'),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final e = _filtered[i];
                      final selected = wide && _selected?.id == e.id;
                      return Container(
                        color: selected ? Colors.blueGrey.shade50 : null,
                        child: Opacity(
                          opacity: e.isArchived ? 0.6 : 1,
                          child: ListTile(
                            leading: const Icon(Icons.precision_manufacturing, size: 36),
                            title: Text(e.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text([
                              [e.brand, e.model].whereType<String>().join(' '),
                              'зав. № ${e.serialNumber ?? '—'}',
                              e.location ?? '',
                            ].where((s) => s.isNotEmpty).join(' · '),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: e.isArchived
                                ? const Chip(label: Text('архив'))
                                : null,
                            onTap: () => _openDetail(e, wide),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _chip(String label, {String? id}) {
    final value = id ?? label;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _site == value,
        onSelected: (_) => setState(() => _site = value),
      ),
    );
  }
}
