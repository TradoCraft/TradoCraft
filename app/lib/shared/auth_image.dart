import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';

/// A picture behind a login: fetched with the session's credentials (a plain network image
/// would not send them) and shown from memory.
class AuthImage extends StatefulWidget {
  const AuthImage({
    super.key,
    required this.dio,
    required this.path,
    this.alt = '',
    this.maxHeight = 360,
  });

  final Dio dio;
  final String path;
  final String alt;
  final double maxHeight;

  @override
  State<AuthImage> createState() => _AuthImageState();
}

class _AuthImageState extends State<AuthImage> {
  late Future<Uint8List> _bytes = _load();

  Future<Uint8List> _load() async {
    final r = await widget.dio.get<List<int>>(
      widget.path,
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(r.data ?? const []);
  }

  @override
  void didUpdateWidget(AuthImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _bytes = _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        if (snap.hasData) {
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            child: Image.memory(
              snap.data!,
              semanticLabel: widget.alt,
              errorBuilder: (_, _, _) => Text('[${widget.alt}]'),
            ),
          );
        }
        if (snap.hasError) return Text('[${widget.alt}]');
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      },
    );
  }
}
