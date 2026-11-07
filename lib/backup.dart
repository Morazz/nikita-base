import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'local_sql.dart';

// Экспорт/импорт базы: SQLite-файл + папка фото в один zip
class BackupService {
  static Future<String?> exportBackup(BuildContext context) async {
    final data = await LocalSql.dataDir();
    final dbFile = File(p.join(data.path, 'oborudovanie.db'));
    if (!await dbFile.exists()) return null;

    final ts = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: 'Сохранить резервную копию базы',
      fileName: 'oborudovanie_backup_$ts.zip',
    );
    if (picked == null) return null; // отмена

    await LocalSql.close(); // чтобы файл не был занят
    try {
      final encoder = ZipFileEncoder();
      encoder.create(picked);
      encoder.addFile(dbFile, 'oborudovanie.db');
      await encoder.addDirectory(LocalSql.photoDir, includeDirName: false);
      encoder.close();
      return picked;
    } finally {
      await LocalSql.db(); // вернуть соединение
    }
  }

  static Future<bool> importBackup() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    final path = res?.files.single.path;
    if (path == null) return false;

    final bytes = await File(path).readAsBytes();
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return false; // битый/не zip
    }

    ArchiveFile? dbEntry;
    for (var f in archive.files) {
      if (f.isFile && f.name == 'oborudovanie.db') {
        dbEntry = f;
        break;
      }
    }
    if (dbEntry == null) return false; // не наш архив

    await LocalSql.close();
    try {
      // база
      await File(p.join(data.path, 'oborudovanie.db'))
          .writeAsBytes(dbEntry.content as List<int>);
      // фото: очистить и распаковать заново
      final photoDir = LocalSql.photoDir;
      if (await photoDir.exists()) await photoDir.delete(recursive: true);
      await photoDir.create(recursive: true);
      for (var f in archive.files) {
        // защита от path traversal (имена вида ../../)
        final name = f.name.replaceAll('\\', '/');
        if (name.contains('..')) continue;
        if (f.isFile && f.name != 'oborudovanie.db') {
          final out = File('${photoDir.path}/$name');
          await out.parent.create(recursive: true);
          await out.writeAsBytes(f.content as List<int>);
        }
      }
    } finally {
      await LocalSql.db();
    }
    return true;
  }
}
