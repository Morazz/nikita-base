import 'package:flutter/material.dart';
import '../local_db.dart';
import '../models.dart';
import '../supabase_client.dart';
import 'add_part_screen.dart';
import 'part_detail_screen.dart';

// Десктопная раскладка: слева список деталей, справа карточка выбранной
class PartsListScreen extends StatefulWidget {
  const PartsListScreen({super.key});
  @override
  State<PartsListScreen> createState() => _State();
}

class _State extends State<PartsListScreen> {
  List<Part> _parts = [];
  String _q = '';
  double? _fd;
  double? _fD;
  double? _fB;
  String _flt = 'Все'; // Все | Подшипники | Дефицит
  int _sort = 0;       // 0 — по названию, 1 — по остатку
  Part? _selected;
  bool _loading = true;

  static const double _kWideBreakpoint = 1000;

  bool get _dimFilter => _fd != null || _fD != null || _fB != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _parts = LocalDb.all(LocalDb.parts).map((e) {
        e['stock'] = LocalDb.stock.get(e['id']) ?? 0;
        return Part.fromMap(e);
      }).toList()..sort((a, b) => a.name.compareTo(b.name));
      _loading = false;
    });
    try {
      final rows = await supabase.from('parts').select().order('name');
      final stock = await fetchStock();
      setState(() {
        _parts = (rows as List).map((e) {
          e['stock'] = stock[e['id']] ?? 0;
          return Part.fromMap(e);
        }).toList();
      });
    } catch (_) {}
  }

  List<Part> get _filtered {
    final q = _q.trim().toLowerCase();
    final num = double.tryParse(q.replaceAll(',', '.'));
    List<Part> rows = _parts.where((p) {
      if (_flt == 'Подшипники' && !p.isBearing) return false;
      if (_flt == 'Дефицит' && p.stock > 2) return false;
      if (_dimFilter) {
        if (!p.isBearing) return false;
        bool ok = true;
        if (_fd != null) ok = ok && p.innerD != null && (p.innerD! - _fd!).abs() < 0.001;
        if (_fD != null) ok = ok && p.outerD != null && (p.outerD! - _fD!).abs() < 0.001;
        if (_fB != null) ok = ok && p.widthB != null && (p.widthB! - _fB!).abs() < 0.001;
        return ok;
      }
      if (q.isEmpty) return true;
      if (p.name.toLowerCase().contains(q)
          || (p.article ?? '').toLowerCase().contains(q)
          || (p.bearingType ?? '').toLowerCase().contains(q)) return true;
      if (num != null) {
        bool eq(double? v) => v != null && (v - num).abs() < 0.001;
        return eq(p.innerD) || eq(p.outerD) || eq(p.widthB);
      }
      return false;
    }).toList();
    if (_sort == 1) rows.sort((a, b) => a.stock.compareTo(b.stock));
    else rows.sort((a, b) => a.name.compareTo(b.name));
    return rows;
  }

  void _onDetailChanged() {
    final id = _selected?.id;
    _load().then((_) {
      if (id == null) return;
      final i = _parts.indexWhere((x) => x.id == id);
      setState(() => _selected = i >= 0 ? _parts[i] : null);
    });
  }

  void _openDetail(Part p, bool wide) {
    if (wide) {
      setState(() => _selected = p);
    } else {
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => PartDetailScreen(part: p))).then((_) => _load());
    }
  }

  Future<void> _pickDims() async {
    final d = TextEditingController(text: _fd?.toString() ?? '');
    final D = TextEditingController(text: _fD?.toString() ?? '');
    final B = TextEditingController(text: _fB?.toString() ?? '');
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подбор подшипника по размерам'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: d, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'd (внутренний), мм'),
          ),
          TextField(
            controller: D, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'D (наружный), мм'),
          ),
          TextField(
            controller: B, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'B (ширина), мм'),
          ),
          const SizedBox(height: 8),
          Text('Можно заполнить не все поля',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'clear'),
            child: const Text('Сбросить'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'apply'),
              child: const Text('Подобрать')),
        ],
      ),
    );
    if (res == 'clear') {
      setState(() { _fd = _fD = _fB = null; });
    } else if (res == 'apply') {
      setState(() {
        _fd = double.tryParse(d.text.replaceAll(',', '.'));
        _fD = double.tryParse(D.text.replaceAll(',', '.'));
        _fB = double.tryParse(B.text.replaceAll(',', '.'));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= _kWideBreakpoint;
    final list = _buildList(wide);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Детали'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Сортировка',
            icon: const Icon(Icons.sort),
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                  value: 0, checked: _sort == 0, child: const Text('По названию')),
              CheckedPopupMenuItem(
                  value: 1, checked: _sort == 1, child: const Text('По остатку')),
            ],
          ),
          IconButton(
            tooltip: 'Подбор по размерам',
            icon: Icon(_dimFilter ? Icons.tune : Icons.tune_outlined),
            onPressed: _pickDims,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_parts',
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AddPartScreen()));
          _load();
        },
        child: const Icon(Icons.add),
      ),
      body: wide
          ? Row(children: [
              SizedBox(width: 430, child: list),
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
          child: Text('Выберите деталь в списке слева',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)));
    }
    final fresh = _parts.firstWhere((x) => x.id == sel.id, orElse: () => sel);
    return PartDetailScreen(
      key: ValueKey('part-${fresh.id}'),
      part: fresh,
      embedded: true,
      onChanged: _onDetailChanged,
    );
  }

  Widget _buildList(bool wide) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Поиск по названию или артикулу'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: ['Все', 'Подшипники', 'Дефицит'].map((f) =>
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(f),
                  selected: _flt == f,
                  onSelected: (_) => setState(() => _flt = f),
                ),
              )).toList()),
        ),
        if (_dimFilter)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(children: [
              ActionChip(
                avatar: const Icon(Icons.tune, size: 18),
                label: Text([
                  if (_fd != null) 'd=$_fd',
                  if (_fD != null) 'D=$_fD',
                  if (_fB != null) 'B=$_fB',
                ].join(' ')),
                onPressed: _pickDims,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Сбросить подбор',
                onPressed: () => setState(() { _fd = _fD = _fB = null; }),
              ),
            ]),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (context, i) {
                      final p = _filtered[i];
                      final selected = wide && _selected?.id == p.id;
                      return Container(
                        color: selected ? Colors.blueGrey.shade50 : null,
                        child: ListTile(
                          leading: const Icon(Icons.settings, size: 32),
                          title: Text(p.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(p.isBearing
                              ? '${p.bearingType ?? 'подшипник'} · ${p.dims} мм'
                              : 'арт. ${p.article ?? '—'}'),
                          trailing: Text('${p.stock} ${p.unit}',
                              style: TextStyle(
                                color: p.stock <= 2 ? Colors.orange : null,
                                fontWeight: FontWeight.w500,
                              )),
                          onTap: () => _openDetail(p, wide),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
