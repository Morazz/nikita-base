import 'local_db.dart';
import 'supabase_client.dart';

// Локальное приложение — синхронизации с облаком нет.
// Все данные пишутся сразу в локальную базу; при ошибке она
// всплывает на экран (см. глобальный обработчик в main.dart).
// Имя класса и методы сохранены, чтобы не менять экраны.
class SyncService {
  // Обновить локальный кэш (Hive) из базы — вызывается при старте/смене вкладки
  static Future<void> syncAll() async {
    try {
      await pullAll();
    } catch (_) {}
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

  static Future<void> pushOutbox() async {}

  // Сохранить в базу. Ошибки (в т.ч. недостаток на складе) — наружу.
  // Возвращает false (флаг "offline" оставлен для совместимости вызовов).
  static Future<bool> saveOrQueue(String table, Map<String, dynamic> data,
      {String? updateId}) async {
    if (updateId != null) {
      await supabase.from(table).update(data).eq('id', updateId);
    } else {
      await supabase.from(table).insert(data);
    }
    return false;
  }

  static Future<bool> deleteOrQueue(String fn, String id) async {
    await supabase.rpc(fn, params: {'p_id': id});
    return false;
  }

  // Очередь больше не используется — оставлено как пустышка
  static void queue(String table, String op, Map<String, dynamic> data,
      {String? id, String? fn}) {}
}
