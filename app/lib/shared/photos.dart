import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/l10n.dart';
import 'app_icons.dart';

/// A photo as listed by the API: its id (the file id), who added it and its caption.
class PhotoItem {
  const PhotoItem({required this.id, this.caption = '', this.by = ''});
  final String id;
  final String caption;
  final String by;
}

/// A picture chosen on the device, ready to upload.
class PickedPhoto {
  const PickedPhoto(this.bytes, this.filename);
  final Uint8List bytes;
  final String filename;
}

typedef PhotoPicker = Future<List<PickedPhoto>> Function(BuildContext context);

/// A random UUID (v4) chosen by the client: the API treats the same id as the same photo, so an
/// upload that is retried (bad signal, app restarted) does not create a second copy.
String newClientId([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int from, int to) => b
      .sublist(from, to)
      .map((x) => x.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
}

/// Sends a photo: the request body is the image itself.
Future<Response<Object?>> uploadPhoto(
  Dio dio,
  String path,
  PickedPhoto photo, {
  String? caption,
  String? clientId,
}) => dio.post<Object?>(
  path,
  data: photo.bytes,
  queryParameters: {
    'filename': photo.filename,
    'client_id': clientId ?? newClientId(),
    if (caption != null && caption.isNotEmpty) 'caption': caption,
  },
  options: Options(
    contentType: 'application/octet-stream',
    headers: {Headers.contentLengthHeader: photo.bytes.length},
  ),
);

bool get _hasCamera =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Asks whether to take a photo or choose from the gallery, and returns the pictures. Large phone
/// photos are scaled down (long side 2400 px) before they are sent.
Future<List<PickedPhoto>> pickPhotos(BuildContext context) async {
  final l = context.l10n;
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_hasCamera)
            ListTile(
              leading: const Icon(AppIcons.photoCamera),
              title: Text(l.takePhoto),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ListTile(
            leading: const Icon(AppIcons.photoLibrary),
            title: Text(l.choosePhoto),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return const [];
  final picker = ImagePicker();
  final files = source == ImageSource.camera
      ? [
          ?await picker.pickImage(
            source: source,
            maxWidth: 2400,
            maxHeight: 2400,
            imageQuality: 85,
          ),
        ]
      : await picker.pickMultiImage(
          maxWidth: 2400,
          maxHeight: 2400,
          imageQuality: 85,
        );
  return [for (final f in files) PickedPhoto(await f.readAsBytes(), f.name)];
}

/// Thumbnails of the photos of a record, a full-size view on tap, and (when [onAdd] is given) a
/// button to add more. Pictures are fetched with the given client, so they use its login.
class PhotoGallery extends StatefulWidget {
  const PhotoGallery({
    super.key,
    required this.photos,
    required this.dio,
    required this.pathFor,
    this.onAdd,
    this.pick = pickPhotos,
  });

  final List<PhotoItem> photos;
  final Dio dio;

  /// The API path of a photo, from its id.
  final String Function(String photoId) pathFor;

  /// Uploads the chosen pictures; null makes the gallery read-only.
  final Future<void> Function(List<PickedPhoto> photos)? onAdd;
  final PhotoPicker pick;

  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<PhotoGallery> {
  final _cache = <String, Future<Uint8List>>{};
  bool _busy = false;

  Future<Uint8List> _bytes(String id) => _cache.putIfAbsent(id, () async {
    final r = await widget.dio.get<List<int>>(
      widget.pathFor(id),
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(r.data ?? const []);
  });

  Future<void> _add() async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final picked = await widget.pick(context);
    if (picked.isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.onAdd!(picked);
      messenger.showSnackBar(SnackBar(content: Text(l.photosAdded)));
    } catch (e) {
      final data = e is DioException ? e.response?.data : null;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            data is Map && data['message'] is String
                ? data['message'] as String
                : e.toString(),
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _open(PhotoItem p) => showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      child: Stack(
        children: [
          InteractiveViewer(
            child: FutureBuilder<Uint8List>(
              future: _bytes(p.id),
              builder: (context, s) => s.hasData
                  ? Image.memory(s.data!, fit: BoxFit.contain)
                  : const SizedBox(
                      height: 200,
                      child: Center(child: CircularProgressIndicator()),
                    ),
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: IconButton.filledTonal(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              icon: const Icon(AppIcons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${l.photos} (${widget.photos.length})',
              style: theme.textTheme.titleSmall,
            ),
            const Spacer(),
            if (widget.onAdd != null)
              TextButton.icon(
                onPressed: _busy ? null : _add,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppIcons.addAPhoto),
                label: Text(_busy ? l.uploadingPhotos : l.addPhoto),
              ),
          ],
        ),
        if (widget.photos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(l.noPhotos, style: theme.textTheme.bodySmall),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in widget.photos)
                InkWell(
                  key: ValueKey('photo-${p.id}'),
                  onTap: () => _open(p),
                  child: SizedBox(
                    width: 116,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 116,
                          height: 116,
                          child: FutureBuilder<Uint8List>(
                            future: _bytes(p.id),
                            builder: (context, s) => s.hasData
                                ? Image.memory(
                                    s.data!,
                                    fit: BoxFit.cover,
                                    cacheWidth: 240,
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
                        if (p.caption.isNotEmpty)
                          Text(
                            p.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        if (p.by.isNotEmpty)
                          Text(
                            l.photoBy(p.by),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
