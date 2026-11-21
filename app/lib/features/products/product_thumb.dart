import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../shared/app_icons.dart';

/// Maximum total bytes of completed thumbnail payloads retained in memory.
const int maxProductThumbCacheBytes = 8 * 1024 * 1024;

final _cachedBytes = <String, Uint8List>{};
final _inFlight = <String, Future<Uint8List>>{};
int _totalCachedBytes = 0;

@visibleForTesting
void clearProductThumbCache() {
  _cachedBytes.clear();
  _inFlight.clear();
  _totalCachedBytes = 0;
}

Future<Uint8List> _fetchThumb(Dio dio, String productId, String mediaId) {
  final cached = _cachedBytes.remove(mediaId);
  if (cached != null) {
    // Re-insert to mark as most-recently used.
    _cachedBytes[mediaId] = cached;
    return SynchronousFuture<Uint8List>(cached);
  }
  final active = _inFlight[mediaId];
  if (active != null) return active;

  late final Future<Uint8List> future;
  future = () async {
    try {
      final r = await dio.get<List<int>>(
        '/api/v1/products/$productId/media/$mediaId',
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = Uint8List.fromList(r.data ?? const []);
      if (bytes.length <= maxProductThumbCacheBytes) {
        final prev = _cachedBytes.remove(mediaId);
        if (prev != null) _totalCachedBytes -= prev.length;
        while (_totalCachedBytes + bytes.length > maxProductThumbCacheBytes &&
            _cachedBytes.isNotEmpty) {
          final oldestKey = _cachedBytes.keys.first;
          final evicted = _cachedBytes.remove(oldestKey)!;
          _totalCachedBytes -= evicted.length;
        }
        _cachedBytes[mediaId] = bytes;
        _totalCachedBytes += bytes.length;
      }
      return bytes;
    } finally {
      _inFlight.remove(mediaId);
    }
  }();
  _inFlight[mediaId] = future;
  return future;
}

/// The default picture of a product as a small square, for lists. A product without media (or
/// whose default is a video) shows a neutral placeholder. Pictures never change under their id,
/// so they are cached in memory up to [maxProductThumbCacheBytes].
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
    if (old.mediaId != widget.mediaId ||
        old.productId != widget.productId ||
        old.isVideo != widget.isVideo) {
      _load();
    }
  }

  void _load() {
    final id = widget.mediaId;
    if (id == null || widget.isVideo) {
      _bytes = null;
      return;
    }
    final dio = ref.read(dioProvider);
    _bytes = _fetchThumb(dio, widget.productId, id);
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
