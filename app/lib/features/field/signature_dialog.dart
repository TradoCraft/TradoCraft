import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/photos.dart' show newClientId;
import 'offline/offline_queue.dart';
import 'offline/offline_ui.dart' show showQueuedSnack;
import '../../shared/app_icons.dart';

/// The strokes drawn on a [SignaturePad], and the picture made of them.
class SignatureController extends ChangeNotifier {
  final List<List<Offset>> strokes = [];

  bool get isEmpty => strokes.isEmpty;

  void start(Offset p) {
    strokes.add([p]);
    notifyListeners();
  }

  void extend(Offset p) {
    if (strokes.isEmpty) return;
    strokes.last.add(p);
    notifyListeners();
  }

  void clear() {
    strokes.clear();
    notifyListeners();
  }

  /// A black-on-white PNG of the strokes for a pad of [size] (logical pixels), drawn at [scale].
  Future<Uint8List> toPng(Size size, {double scale = 2}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    paintStrokes(canvas, strokes, Colors.black);
    final image = await recorder.endRecording().toImage(
      (size.width * scale).round(),
      (size.height * scale).round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }
}

void paintStrokes(Canvas canvas, List<List<Offset>> strokes, Color color) {
  final paint = Paint()
    ..color = color
    ..strokeWidth = 2.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  for (final s in strokes) {
    if (s.length == 1) {
      canvas.drawCircle(s.first, 1.25, paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
    } else {
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final p in s.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }
}

class _StrokesPainter extends CustomPainter {
  _StrokesPainter(this.controller, this.color) : super(repaint: controller);
  final SignatureController controller;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    paintStrokes(canvas, controller.strokes, color);
  }

  @override
  bool shouldRepaint(_StrokesPainter old) => false;
}

/// A canvas to sign on with a finger, pen or mouse.
class SignaturePad extends StatelessWidget {
  const SignaturePad({
    super.key,
    required this.controller,
    required this.onSize,
    this.height = 200,
  });

  final SignatureController controller;
  final ValueChanged<Size> onSize;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, box.maxHeight);
          onSize(size);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (d) => controller.start(d.localPosition),
            onPanUpdate: (d) => controller.extend(d.localPosition),
            child: CustomPaint(
              key: const ValueKey('signature-canvas'),
              size: size,
              painter: _StrokesPainter(controller, Colors.black),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    context.l10n.signHere,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.black38,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Captures the customer's signature (or that they declined) and stores it on the job. The
/// upload gets its id when the dialog opens, so saving again after a failure changes nothing.
Future<JobDetail?> showSignatureDialog(BuildContext context, JobDetail d) =>
    showDialog<JobDetail>(
      context: context,
      builder: (_) => SignatureDialog(detail: d),
    );

class SignatureDialog extends ConsumerStatefulWidget {
  const SignatureDialog({super.key, required this.detail});
  final JobDetail detail;

  @override
  ConsumerState<SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends ConsumerState<SignatureDialog> {
  final _clientId = newClientId();
  final _pad = SignatureController();
  late final _name = TextEditingController(
    text: widget.detail.job.contactName ?? '',
  );
  final _reason = TextEditingController();
  Size _size = const Size(400, 200);
  bool _declined = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pad.dispose();
    _name.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    final id = widget.detail.job.id;
    if (!_declined && _pad.isEmpty) {
      setState(() => _error = l.drawSignatureFirst);
      return;
    }
    if (_declined ? _reason.text.trim().isEmpty : _name.text.trim().isEmpty) {
      setState(() => _error = _declined ? l.reason : l.signerName);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final queue = ref.read(offlineQueueProvider);
      final label = '${widget.detail.job.number} ${widget.detail.job.title}';
      final name = _name.text.trim();
      final JobDetail? d;
      if (_declined) {
        final reason = _reason.text.trim();
        d = await submitWrite(
          queue,
          type: OpType.decline,
          jobId: id,
          jobLabel: label,
          id: _clientId,
          payload: {'signer_name': name, 'reason': reason},
          online: () => ref
              .read(apiProvider)
              .field
              .declineJobSignature(
                id: id,
                body: DeclinedInput(reason: reason, signerName: name),
              ),
        );
      } else {
        final png = await _pad.toPng(_size);
        d = await submitWrite(
          queue,
          type: OpType.signature,
          jobId: id,
          jobLabel: label,
          id: _clientId,
          payload: {'signer_name': name},
          data: png,
          online: () async {
            final res = await ref
                .read(dioProvider)
                .post<Map<String, dynamic>>(
                  '/api/v1/field/jobs/$id/signature',
                  data: png,
                  queryParameters: {
                    'signer_name': name,
                    'client_id': _clientId,
                  },
                  options: Options(
                    contentType: 'image/png',
                    headers: {Headers.contentLengthHeader: png.length},
                  ),
                );
            return JobDetail.fromJson(res.data!);
          },
        );
      }
      if (!mounted) return;
      if (d == null) showQueuedSnack(context);
      Navigator.pop(context, d);
    } on QueueFullException {
      if (mounted) setState(() => _error = context.l10n.offlineTooLarge);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.customerSignature),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: l.signerName),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.customerDeclinedToSign),
                value: _declined,
                onChanged: _busy ? null : (v) => setState(() => _declined = v),
              ),
              if (_declined)
                TextField(
                  controller: _reason,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: l.reason),
                )
              else ...[
                SignaturePad(controller: _pad, onSize: (s) => _size = s),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(AppIcons.close),
                    label: Text(l.clear),
                    onPressed: _busy ? null : _pad.clear,
                  ),
                ),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: Text(l.save)),
      ],
    );
  }
}
