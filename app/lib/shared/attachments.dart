import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../api/generated/export.dart';
import '../l10n/l10n.dart';
import 'photos.dart';
import 'app_icons.dart';

/// Lets the person choose files to attach (JPEG, PNG, WebP or PDF). Replaced in tests.
typedef AttachmentPicker = Future<List<PickedPhoto>> Function(
  BuildContext context,
);

const _attachmentTypes = XTypeGroup(
  label: 'Images and PDF',
  extensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
  mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'],
  uniformTypeIdentifiers: [
    'public.jpeg',
    'public.png',
    'org.webmproject.webp',
    'com.adobe.pdf',
  ],
);

Future<List<PickedPhoto>> pickAttachmentFiles(BuildContext context) async {
  final files = await openFiles(acceptedTypeGroups: [_attachmentTypes]);
  return [for (final f in files) PickedPhoto(await f.readAsBytes(), f.name)];
}

/// Uploads a file to a ticket (the request body is the file) and returns what the server stored.
/// The same file sent twice with the same client id is stored once.
Future<FileInfo> uploadAttachment(
  Dio dio,
  String path,
  PickedPhoto file, {
  String? clientId,
}) async {
  final r = await dio.post<Map<String, dynamic>>(
    path,
    data: file.bytes,
    queryParameters: {
      'filename': file.filename,
      'client_id': clientId ?? newClientId(),
    },
    options: Options(
      contentType: 'application/octet-stream',
      headers: {Headers.contentLengthHeader: file.bytes.length},
    ),
  );
  return FileInfo.fromJson(r.data!);
}

String fileSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}

/// Shows an image in a dialog, or opens a PDF in the print/preview dialog of the system.
Future<void> openAttachment(
  BuildContext context,
  Dio dio,
  String path,
  FileInfo file,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final r = await dio.get<List<int>>(
      path,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = Uint8List.fromList(r.data ?? const []);
    if (!context.mounted) return;
    if (file.contentType.startsWith('image/')) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: Stack(
            children: [
              InteractiveViewer(
                child: Image.memory(bytes, fit: BoxFit.contain),
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
    } else {
      await Printing.layoutPdf(
        name: file.filename,
        onLayout: (_) async => bytes,
      );
    }
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
  }
}

/// The files of a message, as chips that open the file. [pathFor] gives the API path of a file.
class AttachmentChips extends StatelessWidget {
  const AttachmentChips({
    super.key,
    required this.files,
    required this.dio,
    required this.pathFor,
  });

  final List<FileInfo> files;
  final Dio dio;
  final String Function(String fileId) pathFor;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final f in files)
            ActionChip(
              key: ValueKey('attachment-${f.id}'),
              avatar: Icon(
                f.contentType == 'application/pdf'
                    ? AppIcons.pictureAsPdf
                    : AppIcons.image,
                size: 18,
              ),
              label: Text('${f.filename} · ${fileSize(f.sizeBytes)}'),
              onPressed: () => openAttachment(context, dio, pathFor(f.id), f),
            ),
        ],
      ),
    );
  }
}

/// Files chosen for the message being written: chips that can be removed again, and the button
/// that adds more. Files are uploaded when chosen; [onChanged] reports the list.
class AttachmentComposer extends StatefulWidget {
  const AttachmentComposer({
    super.key,
    required this.dio,
    required this.uploadPath,
    required this.onChanged,
    this.pick = pickAttachmentFiles,
    this.files = const [],
  });

  final Dio dio;
  final String uploadPath;
  final List<FileInfo> files;
  final ValueChanged<List<FileInfo>> onChanged;
  final AttachmentPicker pick;

  @override
  State<AttachmentComposer> createState() => _AttachmentComposerState();
}

class _AttachmentComposerState extends State<AttachmentComposer> {
  bool _busy = false;
  String? _error;

  Future<void> _add() async {
    final picked = await widget.pick(context);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final files = [...widget.files];
    try {
      for (final p in picked) {
        files.add(await uploadAttachment(widget.dio, widget.uploadPath, p));
      }
    } catch (e) {
      final data = e is DioException ? e.response?.data : null;
      _error = data is Map && data['message'] is String
          ? data['message'] as String
          : e.toString();
    }
    widget.onChanged(files);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('attach-file'),
              onPressed: _busy ? null : _add,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AppIcons.attachFile),
              label: Text(_busy ? l.uploadingFile : l.attachFile),
            ),
            for (final f in widget.files)
              InputChip(
                key: ValueKey('pending-${f.id}'),
                avatar: Icon(
                  f.contentType == 'application/pdf'
                      ? AppIcons.pictureAsPdf
                      : AppIcons.image,
                  size: 18,
                ),
                label: Text('${f.filename} · ${fileSize(f.sizeBytes)}'),
                onDeleted: () => widget.onChanged([
                  for (final x in widget.files)
                    if (x.id != f.id) x,
                ]),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            _error ?? l.attachmentsHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _error == null ? null : theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}
