import 'package:flutter/material.dart';
import '../models.dart';
import '../supabase_client.dart';
import 'add_part_screen.dart';
import 'part_detail_screen.dart';

class PartsListScreen extends StatefulWidget {
  const PartsListScreen({super.key});
  @override
  State<PartsListScreen> createState() => _State();
}

class _State extends State<PartsListScreen> {
  List<Part> _parts = [];
  String _q = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await supabase.from('parts').select().order('name');
    final stock = await fetchStock();
    setState(() {
      _parts = (rows as List).map((e) {
        e['stock'] = stock[e['id']] ?? 0;
        return Part.fromMap(e);
      }).toList();
      _loading = false;
    });
  }

  // Поиск: по названию/артикулу/типу; если запрос — число, ищем по d/D/B
  List<Part> get _filtered {
    final q = _q.trim().toLowerCase();
    final num = double.tryParse(q.replaceAll(',', '.'));
    return _parts.where((p) {
      if (q.isEmpty) return true;
      if (p.name.toLowerCase().contains(q)
          || (p.article ?? '').toLowerCase().contains(q)
          || (p.bearingType ?? '').toLowerCase().contains(q)) return true;
      if (num != null) {
        bool eq(double? v) =>
            v != null && (v - num).abs() < 0.001;
        return eq(p.innerD) || eq(p.outerD) || eq(p.widthB);
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Детали')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_parts',
        onPressed: () async {
          await Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AddPartScreen()));
          _load();
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search), hintText: 'Поиск по названию или артикулу'),
              onChanged: (v) => setState(() => _q = v),
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
                        final p = _filtered[i];
                        return ListTile(
                          leading: const Icon(Icons.settings, size: 32),
                          title: Text(p.name),
                          subtitle: Text(p.isBearing
                              ? '${p.bearingType ?? 'подшипник'} · ${p.dims} мм'
                              : 'арт. ${p.article ?? '—'}'),
                          trailing: Text('${p.stock} ${p.unit}',
                              style: TextStyle(
                                color: p.stock <= 2 ? Colors.orange : null,
                                fontWeight: FontWeight.w500,
                              )),
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(
                                builder: (_) => PartDetailScreen(part: p)));
                            _load();
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
