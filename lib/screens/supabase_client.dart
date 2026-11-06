import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'local_sql.dart';

// Автономная замена Supabase: тот же API, но всё хранится в локальной SQLite.
// Благодаря этому все экраны приложения работают без изменений.
final supabase = LocalSupabase();

class LocalSupabase {
  LocalQuery from(String table) => LocalQuery(table);
  final storage = LocalStorage();

  Future<void> rpc(String fn, {Map<String, dynamic>? params}) async {
    final id = params?['p_id'] as String;
    switch (fn) {
      case 'delete_equipment':
        await LocalSql.deleteEquipment(id);
      case 'delete_part':
        await LocalSql.deletePart(id);
      case 'delete_repair':
        await LocalSql.deleteRepair(id);
      default:
        throw ArgumentError('unknown rpc: $fn');
    }
  }
}

class LocalStorage {
  LocalStorageBucket from(String bucket) => LocalStorageBucket();
}

class LocalStorageBucket {
  Future<void> uploadBinary(String path, Uint8List bytes) =>
      LocalSql.savePhoto(path, bytes);
  Future<void> remove(List<String> paths) async {
    for (var path in paths) {
      await LocalSql.removePhoto(path);
    }
  }
  String getPublicUrl(String path) => path; // в локальном режиме не используется
}

class LocalQuery {
  final String table;
  String _cols = '*';
  final List<List<dynamic>> _eq = [];
  String? _orderCol;
  bool _asc = true;
  String? _opType;
  Map<String, dynamic>? _opData;

  LocalQuery(this.table);

  LocalQuery select([String cols = '*']) { _cols = cols; return this; }
  LocalQuery eq(String key, dynamic value) { _eq.add([key, value]); return this; }
  LocalQuery order(String col, {bool ascending = true, bool nullsFirst = false}) {
    _orderCol = col;
    _asc = ascending;
    return this;
  }

  LocalQuery insert(Map<String, dynamic> row) {
    _opType = 'insert';
    _opData = Map<String, dynamic>.from(row);
    return this;
  }

  LocalQuery update(Map<String, dynamic> data) {
    _opType = 'update';
    _opData = Map<String, dynamic>.from(data);
    return this;
  }

  LocalQuery delete() {
    _opType = 'delete';
    _opData = null;
    return this;
  }

  Future<Map<String, dynamic>> single() async {
    final rows = await _run();
    if (rows.isEmpty) throw StateError('Запись не найдена в $table');
    return rows.first as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> maybeSingle() async {
    final rows = await _run();
    return rows.isEmpty ? null : rows.first as Map<String, dynamic>;
  }

  // await работает с любым объектом, у которого есть then
  Future<R> then<R>(FutureOr<R> Function(List<dynamic>) onValue,
          {Function? onError}) =>
      _run().then(onValue, onError: onError);

  String get _where {
    if (_eq.isEmpty) return '';
    return ' where ' +
        List.generate(_eq.length, (i) => '${_eq[i][0]} = ?').join(' and ');
  }

  List<dynamic> get _whereArgs =>
      [for (var e in _eq) e[1]];

  String get _orderBy =>
      _orderCol == null ? '' : ' order by $_orderCol ${_asc ? 'asc' : 'desc'}';

  Future<List<dynamic>> _run() async {
    final d = await LocalSql.db();
    Map<String, dynamic>? inserted;

    if (_opType == 'insert') {
      inserted = _opData!;
      inserted['created_at'] ??= DateTime.now().toIso8601String();
      await d.insert(table, inserted);
    } else if (_opType == 'update') {
      await d.update(table, _opData!,
          where: _where.isEmpty ? null : _where.substring(7),
          whereArgs: _whereArgs);
      if (_eq.isNotEmpty) return [];
    } else if (_opType == 'delete') {
      await d.delete(table,
          where: _where.isEmpty ? null : _where.substring(7),
          whereArgs: _whereArgs);
      return [];
    }

    // --- вложенные выборки (как в Supabase) ---
    if (table == 'machine_parts' && _cols == 'parts(*)') {
      final rows = await d.rawQuery(
        'select parts.* from parts join machine_parts mp on mp.part_id = parts.id'
        '$_where$_orderBy', _whereArgs);
      return [{'parts': Map<String, dynamic>.from(rows.first)} for (var r in rows)];
    }
    if (table == 'machine_parts' && _cols == 'equipment(name, model)') {
      final rows = await d.rawQuery(
        'select equipment.name, equipment.model from equipment'
        ' join machine_parts mp on mp.equipment_id = equipment.id'
        '$_where$_orderBy', _whereArgs);
      return [{'equipment': Map<String, dynamic>.from(r)} for (r in rows)];
    }
    if (table == 'repair_records' && _cols.contains('repair_parts(')) {
      final rows = await d.rawQuery(
          'select * from repair_records$_where$_orderBy', _whereArgs);
      final result = <Map<String, dynamic>>[];
      for (var r in rows) {
        final m = Map<String, dynamic>.from(r);
        final rps = await d.rawQuery(
            'select rp.qty, p.name, p.unit from repair_parts rp'
            ' join parts p on p.id = rp.part_id where rp.repair_id = ?',
            [m['id']]);
        m['repair_parts'] = [
          for (var rp in rps)
            {
              'qty': rp['qty'],
              'parts': {'name': rp['name'], 'unit': rp['unit']},
            }
        ];
        result.add(m);
      }
      return result;
    }

    // --- обычная таблица / представление ---
    if (inserted != null && _cols == '*') {
      return [inserted]; // insert().select().single()
    }
    final rows = await d.rawQuery('select * from $table$_where$_orderBy', _whereArgs);
    return [for (var r in rows) Map<String, dynamic>.from(r)];
  }
}

// Просмотр локального фото на любом экране
class LocalImage extends StatefulWidget {
  final String storagePath;
  final double? width;
  final double? height;
  const LocalImage(this.storagePath,
      {super.key, this.width, this.height});

  @override
  State<LocalImage> createState() => _LocalImageState();
}

class _LocalImageState extends State<LocalImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await LocalSql.readPhoto(widget.storagePath);
    if (mounted) setState(() => _bytes = b?.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    return _bytes == null
        ? Container(
            width: widget.width, height: widget.height, color: Colors.black12)
        : Image.memory(_bytes!,
            width: widget.width, height: widget.height, fit: BoxFit.cover);
  }
}
