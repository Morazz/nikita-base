import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'local_sql.dart';
import 'models.dart';

// Полноэкранный просмотр фото с листанием
void showPhotoViewer(BuildContext context, List<Photo> photos, int startIndex) {
  var index = startIndex;
  showDialog(
    context: context,
    barrierColor: Colors.black87,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final photo = photos[index];
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Stack(
            alignment: Alignment.center,
            children: [
              _ViewerImage(photo.storagePath),
              Positioned(
                top: 8, right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              if (photos.length > 1) ...[
                Positioned(
                  left: 8,
                  child: IconButton(
                    icon: const Icon(Icons.chevron_left,
                        color: Colors.white, size: 36),
                    onPressed: index > 0
                        ? () => setState(() => index--)
                        : null,
                  ),
                ),
                Positioned(
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.chevron_right,
                        color: Colors.white, size: 36),
                    onPressed: index < photos.length - 1
                        ? () => setState(() => index++)
                        : null,
                  ),
                ),
                Positioned(
                  bottom: 12,
                  child: Text('${index + 1} / ${photos.length}',
                      style: const TextStyle(color: Colors.white70)),
                ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

class _ViewerImage extends StatefulWidget {
  final String storagePath;
  const _ViewerImage(this.storagePath);

  @override
  State<_ViewerImage> createState() => _ViewerImageState();
}

class _ViewerImageState extends State<_ViewerImage> {
  List<int>? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await LocalSql.readPhoto(widget.storagePath);
    if (mounted) setState(() => _bytes = b);
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    if (b == null) {
      return const SizedBox(
          width: 300, height: 300,
          child: Center(child: CircularProgressIndicator()));
    }
    return InteractiveViewer(
      maxScale: 5,
      child: Image.memory(Uint8List.fromList(b), fit: BoxFit.contain),
    );
  }
}
