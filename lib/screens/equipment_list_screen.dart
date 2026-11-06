import 'package:flutter/material.dart';
import '../models.dart';
import '../supabase_client.dart';
import 'equipment_detail_screen.dart';
import 'add_equipment_screen.dart';

class EquipmentListScreen extends StatefulWidget {
  const EquipmentListScreen({super.key});
  @override
  State<EquipmentListScreen> createState() => _State();
}

class _State extends State<EquipmentListScreen> {
  String _site = 'Все';
  List<Site> _sites = [];
  List<Equipment> _equipment = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sites = await supabase.from('sites').select();
      final eq = await supabase.from('equipment').select().order('name');
      setState(() {
        _sites = (sites as List).map((e) => Site.fromMap(e)).toList();
        _equipment = (eq as List).map((e) => Equipment.fromMap(e)).toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  // _site хранит: 'Все', 'Архив' или id площадки
  List<Equipment> get _filtered {
    if (_site == 'Архив') return _equipment.where((e) => e.isArchived).toList();
    return _equipment
        .where((e) => !e.isArchived && (_site == 'Все' || e.siteId == _site))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Оборудование')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_equipment',
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AddEquipmentScreen()));
          _load();
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _chip('Все'),
                ..._sites.map((s) => _chip(s.name, id: s.id)),
                _chip('Архив'),
              ],
            ),
          ),
          Expanded(
            child: _error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('Ошибка загрузки: $_error',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      FilledButton(onPressed: _load, child: const Text('Повторить')),
                    ]),
                  )
                : _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) {
                        final e = _filtered[i];
                        return Opacity(
                          opacity: e.isArchived ? 0.6 : 1,
                          child: ListTile(
                            leading: const Icon(Icons.precision_manufacturing, size: 36),
                            title: Text(e.name),
                            subtitle: Text([
                              [e.brand, e.model].whereType<String>().join(' '),
                              'зав. № ${e.serialNumber ?? '—'}',
                              e.location ?? '',
                            ].where((s) => s.isNotEmpty).join(' · ')),
                            trailing: e.isArchived
                                ? const Chip(label: Text('архив'))
                                : null,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => EquipmentDetailScreen(equipment: e)),
                              );
                              _load();
                            },
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
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
