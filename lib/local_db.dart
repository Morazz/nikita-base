import 'dart:typed_data';
import 'package:hive_flutter/hive_flutter.dart';

// Локальный кэш данных и очередь синхронизации (Hive).
// Работает в вебе и на десктопе. SQL-база — в local_sql.dart.
class LocalDb {
  static late Box<Map<dynamic, dynamic>> sites;
  static late Box<Map<dynamic, dynamic>> equipment;
  static late Box<Map<dynamic, dynamic>> parts;
  static late Box<Map<dynamic, dynamic>> photos;
  static late Box<Map<dynamic, dynamic>> repairs;
  static late Box<Map<dynamic, dynamic>> movements;
  static late Box<Map<dynamic, dynamic>> machineParts;
  static late Box<int> stock;
  static late Box<Map<dynamic, dynamic>> outbox;
  static late Box<Uint8List> pendingPhotos;

  // path — папка данных рядом с программой; без него — стандартное место ОС
  static Future<void> init({String? path}) async {
    if (path != null) {
      Hive.init(path);
    } else {
      await Hive.initFlutter();
    }
    sites = await Hive.openBox('sites');
    equipment = await Hive.openBox('equipment');
    parts = await Hive.openBox('parts');
    photos = await Hive.openBox('photos');
    repairs = await Hive.openBox('repairs');
    movements = await Hive.openBox('movements');
    machineParts = await Hive.openBox('machine_parts');
    stock = await Hive.openBox('stock');
    outbox = await Hive.openBox('outbox');
    pendingPhotos = await Hive.openBox('pending_photos');
  }

  static List<Map<String, dynamic>> all(Box<Map<dynamic, dynamic>> box) =>
      box.values.map((e) => Map<String, dynamic>.from(e)).toList();

  static void replaceAll(Box<Map<dynamic, dynamic>> box, List<dynamic> rows) {
    box.clear();
    for (var r in rows) {
      final m = Map<String, dynamic>.from(r as Map);
      box.put(m['id'], m);
    }
  }

  static void replaceMachineParts(List<dynamic> rows) {
    machineParts.clear();
    for (var r in rows) {
      final m = Map<String, dynamic>.from(r as Map);
      machineParts.put('${m['equipment_id']}_${m['part_id']}', m);
    }
  }

  static void replaceStock(List<dynamic> rows) {
    stock.clear();
    for (var r in rows) {
      stock.put(r['part_id'] as String, (r['stock'] as num).toInt());
    }
  }

  static int nextOutboxKey() =>
      outbox.keys.fold<int>(0, (m, k) => (k as int) > m ? k as int : m) + 1;
}
