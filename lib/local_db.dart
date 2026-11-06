import 'dart:typed_data';
import 'package:hive_flutter/hive_flutter.dart';

// Локальная база (кэш + очередь синхронизации). Работает в вебе и на телефоне.
class LocalDb {
  static late Box<Map<dynamic, dynamic>> sites;
  static late Box<Map<dynamic, dynamic>> equipment;
  static late Box<Map<dynamic, dynamic>> parts;
  static late Box<Map<dynamic, dynamic>> photos;
  static late Box<Map<dynamic, dynamic>> repairs;
  static late Box<Map<dynamic, dynamic>> movements;
  static late Box<Map<dynamic, dynamic>> machineParts;
  static late Box<int> stock;
  static late Box<Map<dynamic, dynamic>> outbox;      // очередь операций
  static late Box<Uint8List> pendingPhotos;           // фото, ждущие загрузки

  static Future<void> init() async {
    await Hive.initFlutter();
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

  // Следующий ключ очереди
  static int nextOutboxKey() =>
      outbox.keys.fold<int>(0, (m, k) => (k as int) > m ? k as int : m) + 1;
}
