import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../app/session.dart';
import '../../shared/app_icons.dart';
import '../../shared/glb_viewer.dart';
import '../../shared/photos.dart' show isGlbBytes, isSvgBytes;

/// Maximum total bytes of completed thumbnail payloads retained in memory.
const int maxProductThumbCacheBytes = 8 * 1024 * 1024;

final _cachedBytes = <String, Uint8List>{};
final _inFlight = <String, Future<Uint8List>>{};
int _totalCachedBytes = 0;
int _cacheEpoch = 0;
String? _activeSessionScope;

/// Clears all cached and in-flight product thumbnails and invalidates any pre-sign-out requests.
void clearProductThumbCache() {
  _cacheEpoch += 1;
  _cachedBytes.clear();
  _inFlight.clear();
  _totalCachedBytes = 0;
  _activeSessionScope = null;
}

String _sessionScopeKey(Session s) =>
    '${s.serverUrl}|${s.devUser ?? ''}|${s.accessToken ?? ''}|${s.companyId ?? ''}';

Future<Uint8List> _fetchThumb(
  Dio dio,
  String sessionScope,
  String productId,
  String mediaId,
) {
  if (_activeSessionScope != null && _activeSessionScope != sessionScope) {
    clearProductThumbCache();
  }
  _activeSessionScope = sessionScope;
  final epoch = _cacheEpoch;
  final cacheKey = '$sessionScope|$mediaId';

  final cached = _cachedBytes.remove(cacheKey);
  if (cached != null) {
    // Re-insert to mark as most-recently used.
    _cachedBytes[cacheKey] = cached;
    return SynchronousFuture<Uint8List>(cached);
  }
  final active = _inFlight[cacheKey];
  if (active != null) return active;

  late final Future<Uint8List> future;
  future = () async {
    try {
      final r = await dio.get<List<int>>(
        '/api/v1/products/$productId/media/$mediaId',
        options: Options(responseType: ResponseType.bytes),
      );
      if (epoch != _cacheEpoch || _activeSessionScope != sessionScope) {
        throw StateError('Thumbnail request cancelled by session change');
      }
      final bytes = Uint8List.fromList(r.data ?? const []);
      if (bytes.length <= maxProductThumbCacheBytes) {
        final prev = _cachedBytes.remove(cacheKey);
        if (prev != null) _totalCachedBytes -= prev.length;
        while (_totalCachedBytes + bytes.length > maxProductThumbCacheBytes &&
            _cachedBytes.isNotEmpty) {
          final oldestKey = _cachedBytes.keys.first;
          final evicted = _cachedBytes.remove(oldestKey)!;
          _totalCachedBytes -= evicted.length;
        }
        _cachedBytes[cacheKey] = bytes;
        _totalCachedBytes += bytes.length;
      }
      return bytes;
    } finally {
      if (epoch == _cacheEpoch) {
        _inFlight.remove(cacheKey);
      }
    }
  }();
  _inFlight[cacheKey] = future;
  return future;
}

/// The default picture of a product as a small square, for lists. A product without media (or
/// whose default is a video) shows a neutral placeholder. Pictures never change under their id,
/// so they are cached in memory up to [maxProductThumbCacheBytes] within the active session.
class ProductThumb extends ConsumerStatefulWidget {
  const ProductThumb({
    super.key,
    required this.productId,
    required this.mediaId,
    this.productCode,
    this.isVideo = false,
    this.isModel = false,
    this.size = 40,
  });

  final String productId;
  final String? mediaId;
  final String? productCode;
  final bool isVideo;
  final bool isModel;
  final double size;

  @override
  ConsumerState<ProductThumb> createState() => _ProductThumbState();
}

class _ProductThumbState extends ConsumerState<ProductThumb> {
  Future<Uint8List>? _bytes;
  Uint8List? _resolvedBytes;
  String? _lastSessionScope;
  final _hoverLink = LayerLink();
  final _hoverController = OverlayPortalController();

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
        old.productCode != widget.productCode ||
        old.isVideo != widget.isVideo ||
        old.isModel != widget.isModel) {
      _load();
    }
  }

  void _load([Session? session]) {
    _resolvedBytes = null;
    final id = widget.mediaId;
    if (widget.isVideo) {
      _bytes = null;
      return;
    }
    if (id == null) {
      final assetPath = tutorialGlbAssetForCode(widget.productCode ?? '');
      if (assetPath == null) {
        _bytes = null;
        return;
      }
      _bytes = rootBundle
          .load(assetPath)
          .then((bd) => bd.buffer.asUint8List());
      return;
    }
    final dio = ref.read(dioProvider);
    final scope = _sessionScopeKey(session ?? ref.read(sessionProvider));
    _lastSessionScope = scope;
    _bytes = _fetchThumb(dio, scope, widget.productId, id);
  }

  Widget _renderBytes(Uint8List bytes, double size, Widget placeholder) {
    if (isGlbBytes(bytes)) {
      return GlbMiniPreview(bytes: bytes);
    }
    if (isSvgBytes(bytes)) {
      return SvgPicture.memory(bytes, fit: BoxFit.contain);
    }
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      cacheWidth: (size * 3).round(),
      errorBuilder: (_, _, _) => placeholder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final scope = _sessionScopeKey(session);
    if (_lastSessionScope != null && _lastSessionScope != scope) {
      _load(session);
    }
    final s = widget.size;
    final theme = Theme.of(context);
    final outline = theme.colorScheme.outline;
    final imageOutline = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.1);
    Widget placeholder(IconData icon) => Center(
      child: Icon(icon, size: s * 0.5, color: outline),
    );
    final thumbBox = SizedBox(
      key: ValueKey('thumb-${widget.productId}'),
      width: s,
      height: s,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: imageOutline),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: widget.isVideo
              ? placeholder(AppIcons.playCircle)
              : _bytes == null
              ? placeholder(
                  widget.isModel ? Icons.view_in_ar_outlined : AppIcons.photo,
                )
              : FutureBuilder<Uint8List>(
                  key: ValueKey('${scope}_${widget.productCode ?? ''}'),
                  future: _bytes,
                  builder: (context, snap) {
                    if (snap.hasData) {
                      _resolvedBytes = snap.data!;
                      return _renderBytes(
                        snap.data!,
                        s,
                        placeholder(AppIcons.brokenImage),
                      );
                    }
                    return snap.hasError
                        ? placeholder(AppIcons.brokenImage)
                        : const SizedBox.shrink();
                  },
                ),
        ),
      ),
    );
    return CompositedTransformTarget(
      link: _hoverLink,
      child: OverlayPortal(
        controller: _hoverController,
        overlayChildBuilder: (_) {
          final bytes = _resolvedBytes;
          if (bytes == null) return const SizedBox.shrink();
          return IgnorePointer(
            child: CompositedTransformFollower(
              link: _hoverLink,
              targetAnchor: Alignment.centerRight,
              followerAnchor: Alignment.centerLeft,
              offset: const Offset(12, 0),
              child: Align(
                alignment: Alignment.topLeft,
                child: Card(
                  key: ValueKey('thumb-hover-${widget.productId}'),
                  elevation: 8,
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: 240,
                    height: 240,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _renderBytes(
                        bytes,
                        240,
                        placeholder(AppIcons.brokenImage),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        child: MouseRegion(
          onEnter: (_) {
            if (_resolvedBytes != null) _hoverController.show();
          },
          onExit: (_) => _hoverController.hide(),
          child: thumbBox,
        ),
      ),
    );
  }
}
