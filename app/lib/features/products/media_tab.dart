import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/file_export.dart';
import '../../shared/photos.dart';

/// One picture or video of a product, as listed by `GET /products/{id}/media`.
class ProductMediaItem {
  const ProductMediaItem({
    required this.id,
    required this.kind,
    required this.filename,
    required this.caption,
    required this.isDefault,
  });

  factory ProductMediaItem.fromJson(Map<String, dynamic> j) => ProductMediaItem(
    id: j['id'] as String,
    kind: j['kind'] as String,
    filename: j['filename'] as String? ?? '',
    caption: j['caption'] as String? ?? '',
    isDefault: j['is_default'] as bool? ?? false,
  );

  final String id;
  final String kind;
  final String filename;
  final String caption;
  final bool isDefault;
  bool get isVideo => kind == 'video';
}

final _mediaProvider = FutureProvider.autoDispose
    .family<List<ProductMediaItem>, String>((ref, productId) async {
      final r = await ref
          .watch(dioProvider)
          .get<List<dynamic>>('/api/v1/products/$productId/media');
      return [
        for (final j in r.data ?? const [])
          ProductMediaItem.fromJson(j as Map<String, dynamic>),
      ];
    });

/// Pictures and videos of a product. The one marked as default is listed first and is the one
/// shown wherever the product has a single picture.
class MediaTab extends ConsumerStatefulWidget {
  const MediaTab({super.key, required this.productId});
  final String productId;

  @override
  ConsumerState<MediaTab> createState() => _MediaTabState();
}

class _MediaTabState extends ConsumerState<MediaTab> {
  final _cache = <String, Future<Uint8List>>{};
  bool _busy = false;

  String get _base => '/api/v1/products/${widget.productId}/media';

  Future<Uint8List> _bytes(String id) {
    final existing = _cache[id];
    if (existing != null) return existing;
    final dio = ref.read(dioProvider);
    final url = '$_base/$id';
    late final Future<Uint8List> future;
    future = () async {
      try {
        final r = await dio.get<List<int>>(
          url,
          options: Options(responseType: ResponseType.bytes),
        );
        return Uint8List.fromList(r.data ?? const []);
      } catch (_) {
        _cache.remove(id);
        rethrow;
      }
    }();
    _cache[id] = future;
    return future;
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    } finally {
      if (mounted) {
        ref.invalidate(_mediaProvider(widget.productId));
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _add() => _run(() async {
    final dio = ref.read(dioProvider);
    final base = _base;
    final files = await ImagePicker().pickMultipleMedia();
    for (final f in files) {
      await uploadPhoto(dio, base, PickedPhoto(await f.readAsBytes(), f.name));
    }
  });

  Future<void> _makeDefault(ProductMediaItem m) => _run(() async {
    final dio = ref.read(dioProvider);
    final base = _base;
    await dio.patch<Object?>('$base/${m.id}', data: {'is_default': true});
  });

  Future<void> _remove(ProductMediaItem m) => _run(() async {
    final dio = ref.read(dioProvider);
    final base = _base;
    await dio.delete<Object?>('$base/${m.id}');
    _cache.remove(m.id);
  });

  Future<void> _open(ProductMediaItem m) async {
    if (m.isVideo) {
      final messenger = ScaffoldMessenger.of(context);
      try {
        final bytes = await _bytes(m.id);
        if (!mounted) return;
        final name = m.filename.split(RegExp(r'[\\/]')).last.trim();
        await saveExport(
          context,
          ref,
          name.isEmpty || name == '.' || name == '..' ? 'video.mp4' : name,
          bytes,
        );
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: FutureBuilder<Uint8List>(
          future: _bytes(m.id),
          builder: (context, s) => s.hasData
              ? InteractiveViewer(child: Image.memory(s.data!))
              : const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                ),
        ),
      ),
    );
  }

  Widget _tile(ProductMediaItem m, bool canWrite) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return SizedBox(
      key: ValueKey('media-${m.id}'),
      width: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _open(m),
            child: Stack(
              children: [
                SizedBox(
                  width: 148,
                  height: 148,
                  child: m.isVideo
                      ? const Center(child: Icon(AppIcons.playCircle, size: 48))
                      : FutureBuilder<Uint8List>(
                          future: _bytes(m.id),
                          builder: (context, s) => s.hasData
                              ? Image.memory(
                                  s.data!,
                                  fit: BoxFit.cover,
                                  cacheWidth: 300,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(AppIcons.brokenImage),
                                )
                              : s.hasError
                              ? const Icon(AppIcons.brokenImage)
                              : const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                        ),
                ),
                if (m.isDefault)
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Chip(
                      key: const ValueKey('media-default-badge'),
                      avatar: const Icon(AppIcons.star, size: 16),
                      label: Text(l.defaultMedia),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            m.caption.isNotEmpty ? m.caption : m.filename,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          if (canWrite)
            Row(
              children: [
                if (!m.isDefault)
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: _busy ? null : () => _makeDefault(m),
                        child: Text(
                          l.makeDefault,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  )
                else
                  const Spacer(),
                IconButton(
                  tooltip: l.delete,
                  icon: const Icon(AppIcons.delete),
                  onPressed: _busy ? null : () => _remove(m),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final canWrite = can(ref, 'products.write');
    final media = ref.watch(_mediaProvider(widget.productId));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (canWrite)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              icon: const Icon(AppIcons.addAPhoto),
              label: Text(l.addPictureOrVideo),
              onPressed: _busy ? null : _add,
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
        media.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(errorMessage(e)),
          data: (items) => items.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(l.noMedia),
                )
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [for (final m in items) _tile(m, canWrite)],
                  ),
                ),
        ),
      ],
    );
  }
}
