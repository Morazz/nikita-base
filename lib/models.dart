import 'supabase_client.dart';

class Site {
  final String id;
  final String name;
  Site({required this.id, required this.name});
  factory Site.fromMap(Map<String, dynamic> m) => Site(id: m['id'], name: m['name']);
}

class Equipment {
  final String id;
  final String siteId;
  final String name;
  final String? brand;
  final String? model;
  final String? serialNumber;
  final String? manufacturer;
  final int? year;
  final String? location;
  final String? comment;
  final String status; // active | archived
  Equipment({
    required this.id, required this.siteId, required this.name, this.brand,
    this.model, this.serialNumber, this.manufacturer, this.year,
    this.location, this.comment, this.status = 'active',
  });
  factory Equipment.fromMap(Map<String, dynamic> m) => Equipment(
    id: m['id'], siteId: m['site_id'], name: m['name'], brand: m['brand'],
    model: m['model'], serialNumber: m['serial_number'],
    manufacturer: m['manufacturer'], year: m['year'],
    location: m['location'], comment: m['comment'], status: m['status'],
  );
  bool get isArchived => status == 'archived';
}

class Part {
  final String id;
  final String name;
  final String? article;
  final String? manufacturer;
  final String? comment;
  final String unit;
  final int stock; // из view part_stock
  // параметры подшипника
  final bool isBearing;
  final String? bearingType;
  final double? innerD;   // d, мм
  final double? outerD;   // D, мм
  final double? widthB;   // B, мм
  Part({required this.id, required this.name,
        this.article, this.manufacturer, this.comment,
        this.unit = 'шт', this.stock = 0,
        this.isBearing = false, this.bearingType,
        this.innerD, this.outerD, this.widthB});
  factory Part.fromMap(Map<String, dynamic> m) => Part(
    id: m['id'], name: m['name'],
    article: m['article'], manufacturer: m['manufacturer'], comment: m['comment'],
    unit: m['unit'] ?? 'шт', stock: m['stock'] ?? 0,
    isBearing: m['is_bearing'] == true || m['is_bearing'] == 1,
    bearingType: m['bearing_type'],
    innerD: (m['inner_d'] as num?)?.toDouble(),
    outerD: (m['outer_d'] as num?)?.toDouble(),
    widthB: (m['width_b'] as num?)?.toDouble(),
  );
  String get dims => [innerD, outerD, widthB]
      .map((v) => v == null ? '—' : v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1))
      .join('×');
}

class Photo {
  final String id;
  final String kind; // general | nameplate | extra
  final String storagePath;
  final int position;
  Photo({required this.id, required this.kind, required this.storagePath,
      this.position = 0});
  factory Photo.fromMap(Map<String, dynamic> m) =>
      Photo(id: m['id'], kind: m['kind'], storagePath: m['storage_path'],
          position: m['position'] ?? 0);
}

class Repair {
  final String id;
  final String equipmentId;
  final DateTime date;
  final String description;
  final String? comment;
  Repair({required this.id, required this.equipmentId,
          required this.date, required this.description, this.comment});
  factory Repair.fromMap(Map<String, dynamic> m) => Repair(
    id: m['id'], equipmentId: m['equipment_id'],
    date: DateTime.parse(m['date']), description: m['description'],
    comment: m['comment'],
  );
}

// Публичная ссылка на фото из Storage
String photoUrl(String storagePath) => supabase.storage
    .from('photos')
    .getPublicUrl(storagePath);


class PartMovement {
  final String id;
  final String type; // in | out | writeoff
  final int qty;
  final String? comment;
  final DateTime createdAt;
  PartMovement({required this.id, required this.type, required this.qty,
                this.comment, required this.createdAt});
  factory PartMovement.fromMap(Map<String, dynamic> m) => PartMovement(
    id: m['id'], type: m['type'], qty: m['qty'], comment: m['comment'],
    createdAt: DateTime.parse(m['created_at']),
  );
}

// Остатки по всем деталям из view part_stock
Future<Map<String, int>> fetchStock() async {
  final rows = await supabase.from('part_stock').select();
  return {
    for (var r in rows as List)
      (r['part_id'] as String): (r['stock'] as num).toInt(),
  };
}

class Document {
  final String id;
  final String equipmentId;
  final String name;          // исходное имя файла
  final String storagePath;   // путь относительно папки data
  final int? size;            // байт
  Document({required this.id, required this.equipmentId,
            required this.name, required this.storagePath, this.size});
  factory Document.fromMap(Map<String, dynamic> m) => Document(
    id: m['id'], equipmentId: m['equipment_id'], name: m['name'],
    storagePath: m['storage_path'], size: m['size'],
  );
  String get ext => name.contains('.') ? name.split('.').last.toLowerCase() : '';
}
