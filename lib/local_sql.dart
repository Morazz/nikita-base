import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Локальная SQLite-база. Полностью автономная, интернет не нужен.
class LocalSql {
  static Database? _db;
  static Directory? _photoDir;

  static Future<Database> db() async {
    if (_db != null) return _db!;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final docs = await getApplicationDocumentsDirectory();
    _photoDir = Directory(p.join(docs.path, 'oborudovanie_photos'));
    await _photoDir!.create(recursive: true);
    _db = await databaseFactory.openDatabase(p.join(docs.path, 'oborudovanie.db'));
    await _db!.execute('''
      create table if not exists sites (
        id text primary key, name text not null unique, note text, created_at text
      );
      create table if not exists equipment (
        id text primary key, site_id text not null, name text not null,
        brand text, model text, serial_number text, manufacturer text,
        year integer, location text, comment text,
        status text not null default 'active', created_at text
      );
      create table if not exists parts (
        id text primary key, name text not null, article text,
        manufacturer text, comment text, unit text not null default 'шт',
        is_bearing integer not null default 0, bearing_type text,
        inner_d real, outer_d real, width_b real, created_at text
      );
      create table if not exists photos (
        id text primary key, owner_type text not null, owner_id text not null,
        kind text not null, storage_path text not null,
        position integer not null default 0, created_at text
      );
      create table if not exists machine_parts (
        equipment_id text not null, part_id text not null,
        created_at text, primary key (equipment_id, part_id)
      );
      create table if not exists part_movements (
        id text primary key, part_id text not null,
        type text not null check (type in ('in','out','writeoff')),
        qty integer not null, equipment_id text, repair_id text,
        comment text, created_at text
      );
      create table if not exists repair_records (
        id text primary key, equipment_id text not null, date text not null,
        description text not null, comment text, created_at text
      );
      create table if not exists repair_parts (
        repair_id text not null, part_id text not null, qty integer not null,
        primary key (repair_id, part_id)
      );
      create view if not exists part_stock as
        select p.id as part_id,
          coalesce(sum(case m.type when 'in' then m.qty else -m.qty end), 0) as stock
        from parts p left join part_movements m on m.part_id = p.id
        group by p.id;
      create trigger if not exists trg_check_stock after insert on part_movements
      begin
        select case when (
          select coalesce(sum(case type when 'in' then qty else -qty end), 0)
          from part_movements where part_id = new.part_id) < 0
        then raise(abort, 'Недостаточно деталей на складе') end;
      end;
    ''');

    // наследие ранних версий: записи с пустым id восстанавливаем по rowid
    // (файлы фото не трогаем — только чиним ссылки в базе)
    await _db!.execute("""
      update equipment set id = 'fix-' || rowid where id is null;
      update parts set id = 'fix-' || rowid where id is null;
      update photos set id = 'fix-' || rowid where id is null;
      update part_movements set id = 'fix-' || rowid where id is null;
      update repair_records set id = 'fix-' || rowid where id is null;
    """);

    final now = DateTime.now().toIso8601String();
    var i = 0;
    for (var name in ['Калинина', 'Корженевского', 'Инженерная']) {
      i++;
        await _db!.rawInsert(
          'insert or ignore into sites (id, name, created_at) values (?, ?, ?)',
          ['seed-$i', name, now]);
    }
    return _db!;
  }

  // Закрыть соединение (нужно перед копированием/заменой файла базы)
  static Future<void> close() async {
    final d = _db;
    _db = null;
    if (d != null) await d.close();
  }

  static File photoFile(String storagePath) =>
      File(p.join(_photoDir!.path, storagePath));

  static Future<void> savePhoto(String storagePath, List<int> bytes) async {
    final f = photoFile(storagePath);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
  }

  static Future<List<int>?> readPhoto(String storagePath) async {
    final f = photoFile(storagePath);
    return await f.exists() ? await f.readAsBytes() : null;
  }

  static Future<void> removePhoto(String storagePath) async {
    final f = photoFile(storagePath);
    if (await f.exists()) await f.delete();
  }

  static Future<void> deleteEquipment(String id) async {
    final d = await db();
    await d.delete('photos', where: "owner_type='equipment' and owner_id=?", whereArgs: [id]);
    await d.delete('part_movements', where: 'equipment_id=?', whereArgs: [id]);
    final repairs = await d.rawQuery('select id from repair_records where equipment_id=?', [id]);
    for (var r in repairs) {
      await d.delete('repair_parts', where: 'repair_id=?', whereArgs: [r['id']]);
      await d.delete('part_movements', where: 'repair_id=?', whereArgs: [r['id']]);
    }
    await d.delete('repair_records', where: 'equipment_id=?', whereArgs: [id]);
    await d.delete('machine_parts', where: 'equipment_id=?', whereArgs: [id]);
    await d.delete('equipment', where: 'id=?', whereArgs: [id]);
  }

  static Future<void> deletePart(String id) async {
    final d = await db();
    await d.delete('photos', where: "owner_type='part' and owner_id=?", whereArgs: [id]);
    await d.delete('part_movements', where: 'part_id=?', whereArgs: [id]);
    await d.delete('repair_parts', where: 'part_id=?', whereArgs: [id]);
    await d.delete('machine_parts', where: 'part_id=?', whereArgs: [id]);
    await d.delete('parts', where: 'id=?', whereArgs: [id]);
  }

  static Future<void> deleteRepair(String id) async {
    final d = await db();
    await d.delete('photos', where: "owner_type='repair' and owner_id=?", whereArgs: [id]);
    await d.delete('part_movements', where: 'repair_id=?', whereArgs: [id]);
    await d.delete('repair_parts', where: 'repair_id=?', whereArgs: [id]);
    await d.delete('repair_records', where: 'id=?', whereArgs: [id]);
  }
}
