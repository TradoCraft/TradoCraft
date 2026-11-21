import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../shared/app_icons.dart';

/// The default picture of a product as a small square, for lists. A product without media (or
/// whose default is a video) shows a neutral placeholder. Pictures never change under their id,
/// so they are fetched once per session.
class ProductThumb extends ConsumerStatefulWidget {
  const ProductThumb({
    super.key,
    required this.productId,
    required this.mediaId,
    this.isVideo = false,
    this.size = 40,
  });

  final String productId;
  final String? mediaId;
  final bool isVideo;
  final double size;

  @override
  ConsumerState<ProductThumb> createState() => _ProductThumbState();
}

final _cache = <String, Future<Uint8List>>{};

class _ProductThumbState extends ConsumerState<ProductThumb> {
  Future<Uint8List>? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ProductThumb old) {
    super.didUpdateWidget(old);
    if (old.mediaId != widget.mediaId) _load();
  }

  void _load() {
    final id = widget.mediaId;
    if (id == null || widget.isVideo) {
      _bytes = null;
      return;
    }
    final dio = ref.read(dioProvider);
    _bytes = _cache.putIfAbsent(id, () async {
      final r = await dio.get<List<int>>(
        '/api/v1/products/${widget.productId}/media/$id',
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(r.data ?? const []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final outline = Theme.of(context).colorScheme.outline;
    Widget placeholder(IconData icon) => Center(
      child: Icon(icon, size: s * 0.5, color: outline),
    );
    return SizedBox(
      key: ValueKey('thumb-${widget.productId}'),
      width: s,
      height: s,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: widget.isVideo
            ? placeholder(AppIcons.playCircle)
            : _bytes == null
            ? placeholder(AppIcons.photo)
            : FutureBuilder<Uint8List>(
                future: _bytes,
                builder: (context, snap) => snap.hasData
                    ? Image.memory(
                        snap.data!,
                        fit: BoxFit.cover,
                        cacheWidth: (s * 3).round(),
                        errorBuilder: (_, _, _) =>
                            placeholder(AppIcons.brokenImage),
                      )
                    : snap.hasError
                    ? placeholder(AppIcons.brokenImage)
                    : const SizedBox.shrink(),
              ),
      ),
    );
  }
}
