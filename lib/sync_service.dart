import 'local_db.dart';
import 'supabase_client.dart';

// Синхронизация: сначала отправляем накопленные изменения (outbox), потом
// подтягиваем свежие данные из облака в локальный кэш.
class SyncService {
  static bool _running = false;

  static Future<void> syncAll() async {
    if (_running) return;
    _running = true;
    try {
      await pushOutbox();
      await pullAll();
    } catch (_) {
      // нет сети — просто остаёмся на локальных данных
    }
    _running = false;
  }

  static Future<void> pullAll() async {
    final sites = await supabase.from('sites').select();
    LocalDb.replaceAll(LocalDb.sites, sites as List);

    final eq = await supabase.from('equipment').select();
    LocalDb.replaceAll(LocalDb.equipment, eq as List);

    final parts = await supabase.from('parts').select();
    LocalDb.replaceAll(LocalDb.parts, parts as List);

    final photos = await supabase.from('photos').select();
    LocalDb.replaceAll(LocalDb.photos, photos as List);

    final repairs = await supabase.from('repair_records')
        .select('*, repair_parts(qty, parts(name, unit))');
    LocalDb.replaceAll(LocalDb.repairs, repairs as List);

    final mps = await supabase.from('machine_parts').select();
    LocalDb.replaceMachineParts(mps as List);

    final stock = await supabase.from('part_stock').select();
    LocalDb.replaceStock(stock as List);

    final movements = await supabase.from('part_movements').select()
        .order('created_at', ascending: false);
    LocalDb.replaceAll(LocalDb.movements, movements as List);
  }

  static Future<void> pushOutbox() async {
    final keys = LocalDb.outbox.keys.map((k) => k as int).toList()..sort();
    for (var k in keys) {
      final op = Map<String, dynamic>.from(LocalDb.outbox.get(k)!);
      try {
        await _apply(op);
        LocalDb.outbox.delete(k);
      } catch (_) {
        break; // сеть пропала — остальное ждёт следующего раза
      }
    }
    // выгружаем накопленные фото
    for (var path in LocalDb.pendingPhotos.keys.toList()) {
      try {
        final bytes = LocalDb.pendingPhotos.get(path)!;
        await supabase.storage.from('photos').uploadBinary(path, bytes);
        LocalDb.pendingPhotos.delete(path);
      } catch (_) {
        break;
      }
    }
  }

  static Future<void> _apply(Map<String, dynamic> op) async {
    final table = op['table'] as String;
    final data = Map<String, dynamic>.from(op['data'] as Map);
    switch (op['op'] as String) {
      case 'insert':
        await supabase.from(table).insert(data);
      case 'update':
        await supabase.from(table).update(data).eq('id', op['id']);
      case 'delete':
        await supabase.rpc(op['fn'] as String, params: {'p_id': op['id']});
    }
  }

  // Поставить операцию в очередь (вызывается при неудачной записи в сеть)
  static void queue(String table, String op, Map<String, dynamic> data,
      {String? id, String? fn}) {
    LocalDb.outbox.put(LocalDb.nextOutboxKey(), {
      'table': table, 'op': op, 'data': data, 'id': id, 'fn': fn,
    });
  }

  // Ошибки данных (не «офлайн») — не кладём в очередь, а пробрасываем
  static bool _isDataError(Object e) {
    final msg = e.toString();
    return msg.contains('Недостаточно') ||
        msg.contains('UNIQUE constraint') ||
        msg.contains('not null') ||
        msg.contains('CHECK constraint');
  }

  // Сохранить в сеть; при неудаче — поставить в очередь (true = было в offline)
  static Future<bool> saveOrQueue(String table, Map<String, dynamic> data,
      {String? updateId}) async {
    try {
      if (updateId != null) {
        await supabase.from(table).update(data).eq('id', updateId);
      } else {
        await supabase.from(table).insert(data);
      }
      return false;
    } catch (e) {
      if (_isDataError(e)) rethrow;
      if (updateId != null) {
        queue(table, 'update', data, id: updateId);
      } else {
        queue(table, 'insert', data);
      }
      return true;
    }
  }

  // Удалить в сети; при неудаче — поставить в очередь
  static Future<bool> deleteOrQueue(String fn, String id) async {
    try {
      await supabase.rpc(fn, params: {'p_id': id});
      return false;
    } catch (_) {
      queue('', 'delete', {}, id: id, fn: fn);
      return true;
    }
  }
}
