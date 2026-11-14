import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// A piece of inline text with its style. A link has [url]; an image has [image] (the id used as
/// `![alt](image:ID)`) and [text] is its description.
class MdSpan {
  const MdSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.url,
    this.image,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final String? url;
  final String? image;

  @override
  bool operator ==(Object other) =>
      other is MdSpan &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.code == code &&
      other.url == url &&
      other.image == image;

  @override
  int get hashCode => Object.hash(text, bold, italic, code, url, image);

  @override
  String toString() =>
      'MdSpan($text${bold ? ' b' : ''}${italic ? ' i' : ''}${code ? ' c' : ''}'
      '${url != null ? ' ->$url' : ''}${image != null ? ' img:$image' : ''})';
}

/// Only these kinds of address can be opened from a link; anything else (`javascript:` and the
/// like) is shown as plain text.
bool isSafeLink(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null) return false;
  return u.scheme == 'http' || u.scheme == 'https' || u.scheme == 'mailto';
}

/// Parses `**bold**`, `*italic*`, `_italic_`, `` `code` ``, `[label](url)` and
/// `![alt](image:ID)`. No HTML: angle brackets are ordinary text.
List<MdSpan> parseInline(String s) {
  final out = <MdSpan>[];
  final buf = StringBuffer();
  var bold = false, italic = false;

  void flush() {
    if (buf.isEmpty) return;
    out.add(MdSpan(buf.toString(), bold: bold, italic: italic));
    buf.clear();
  }

  bool wordChar(int i) {
    if (i < 0 || i >= s.length) return false;
    return RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(s[i]);
  }

  (String, String, int)? link(int start) {
    final close = s.indexOf(']', start + 1);
    if (close < 0 || close + 1 >= s.length || s[close + 1] != '(') return null;
    final end = s.indexOf(')', close + 2);
    if (end < 0) return null;
    return (
      s.substring(start + 1, close),
      s.substring(close + 2, end).trim(),
      end + 1,
    );
  }

  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == '\\' && i + 1 < s.length && '*_`[]()!\\#'.contains(s[i + 1])) {
      buf.write(s[i + 1]);
      i += 2;
      continue;
    }
    if (c == '`') {
      final end = s.indexOf('`', i + 1);
      if (end > i) {
        flush();
        out.add(MdSpan(s.substring(i + 1, end), code: true));
        i = end + 1;
        continue;
      }
    }
    if (c == '!' && i + 1 < s.length && s[i + 1] == '[') {
      final l = link(i + 1);
      if (l != null) {
        flush();
        if (l.$2.startsWith('image:')) {
          out.add(MdSpan(l.$1, image: l.$2.substring(6).trim()));
        } else if (l.$1.isNotEmpty) {
          out.add(MdSpan(l.$1, italic: true));
        }
        i = l.$3;
        continue;
      }
    }
    if (c == '[') {
      final l = link(i);
      if (l != null) {
        flush();
        final label = l.$1.isEmpty ? l.$2 : l.$1;
        out.add(
          isSafeLink(l.$2)
              ? MdSpan(label, bold: bold, italic: italic, url: l.$2)
              : MdSpan(label, bold: bold, italic: italic),
        );
        i = l.$3;
        continue;
      }
    }
    if (c == '*' && i + 1 < s.length && s[i + 1] == '*') {
      flush();
      bold = !bold;
      i += 2;
      continue;
    }
    if (c == '*' || (c == '_' && !(wordChar(i - 1) && wordChar(i + 1)))) {
      flush();
      italic = !italic;
      i++;
      continue;
    }
    buf.write(c);
    i++;
  }
  flush();
  return out;
}

sealed class MdBlock {
  const MdBlock();
}

class MdHeading extends MdBlock {
  const MdHeading(this.level, this.text);
  final int level;
  final String text;
}

class MdParagraph extends MdBlock {
  const MdParagraph(this.text);
  final String text;
}

class MdList extends MdBlock {
  const MdList(this.ordered, this.items);
  final bool ordered;
  final List<String> items;
}

class MdQuote extends MdBlock {
  const MdQuote(this.text);
  final String text;
}

class MdCode extends MdBlock {
  const MdCode(this.text);
  final String text;
}

class MdRule extends MdBlock {
  const MdRule();
}

final _bullet = RegExp(r'^\s*[-*+]\s+(.*)$');
final _numbered = RegExp(r'^\s*\d+[.)]\s+(.*)$');
final _heading = RegExp(r'^(#{1,6})\s+(.*)$');

/// Splits Markdown into headings, paragraphs, lists, quotes, code blocks and rules.
List<MdBlock> parseBlocks(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final blocks = <MdBlock>[];
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (line.trim().isEmpty) {
      i++;
      continue;
    }
    if (line.trimLeft().startsWith('```')) {
      final code = <String>[];
      i++;
      while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
        code.add(lines[i]);
        i++;
      }
      i++;
      blocks.add(MdCode(code.join('\n')));
      continue;
    }
    final h = _heading.firstMatch(line.trim());
    if (h != null) {
      blocks.add(MdHeading(h.group(1)!.length, h.group(2)!.trim()));
      i++;
      continue;
    }
    if (RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$').hasMatch(line)) {
      blocks.add(const MdRule());
      i++;
      continue;
    }
    if (_bullet.hasMatch(line) || _numbered.hasMatch(line)) {
      final ordered = _numbered.hasMatch(line);
      final items = <String>[];
      while (i < lines.length) {
        final m = (ordered ? _numbered : _bullet).firstMatch(lines[i]);
        if (m == null) break;
        items.add(m.group(1)!.trim());
        i++;
      }
      blocks.add(MdList(ordered, items));
      continue;
    }
    if (line.trimLeft().startsWith('>')) {
      final q = <String>[];
      while (i < lines.length && lines[i].trimLeft().startsWith('>')) {
        q.add(lines[i].trimLeft().substring(1).trim());
        i++;
      }
      blocks.add(MdQuote(q.join(' ')));
      continue;
    }
    final p = <String>[];
    while (i < lines.length &&
        lines[i].trim().isNotEmpty &&
        !_heading.hasMatch(lines[i].trim()) &&
        !_bullet.hasMatch(lines[i]) &&
        !_numbered.hasMatch(lines[i]) &&
        !lines[i].trimLeft().startsWith('```') &&
        !lines[i].trimLeft().startsWith('>')) {
      p.add(lines[i].trim());
      i++;
    }
    blocks.add(MdParagraph(p.join(' ')));
  }
  return blocks;
}

/// Builds the picture for `![alt](image:ID)`.
typedef MarkdownImageBuilder = Widget Function(
  BuildContext context,
  String id,
  String alt,
);

/// Shows simple Markdown: headings, paragraphs, bold, italics, code, lists, quotes, links and
/// pictures that belong to the article. Raw HTML is never interpreted and remote pictures are
/// never loaded.
class MarkdownView extends StatefulWidget {
  const MarkdownView({
    super.key,
    required this.source,
    this.imageBuilder,
    this.onOpenLink,
  });

  final String source;
  final MarkdownImageBuilder? imageBuilder;

  /// Replaced in tests; the default opens the address outside the app.
  final Future<void> Function(String url)? onOpenLink;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  final _recognizers = <TapGestureRecognizer>[];

  void _release() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final custom = widget.onOpenLink;
    if (custom != null) return custom(url);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  List<InlineSpan> _spans(BuildContext context, String text, TextStyle base) {
    final out = <InlineSpan>[];
    for (final s in parseInline(text)) {
      if (s.image != null) {
        final b = widget.imageBuilder;
        out.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: b != null
                ? b(context, s.image!, s.text)
                : Text('[${s.text}]', style: base),
          ),
        );
        continue;
      }
      var style = base.copyWith(
        fontWeight: s.bold ? FontWeight.bold : null,
        fontStyle: s.italic ? FontStyle.italic : null,
      );
      if (s.code) {
        style = style.copyWith(
          fontFamily: 'monospace',
          backgroundColor: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest,
        );
      }
      if (s.url != null) {
        final url = s.url!;
        final r = TapGestureRecognizer()..onTap = () => _open(url);
        _recognizers.add(r);
        style = style.copyWith(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
        );
        out.add(TextSpan(text: s.text, style: style, recognizer: r));
      } else {
        out.add(TextSpan(text: s.text, style: style));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    _release();
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium!;
    Widget rich(String text, TextStyle style) =>
        Text.rich(TextSpan(children: _spans(context, text, style)));
    final children = <Widget>[];
    for (final b in parseBlocks(widget.source)) {
      children.add(switch (b) {
        MdHeading() => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: rich(
            b.text,
            (switch (b.level) {
              1 => theme.textTheme.headlineSmall,
              2 => theme.textTheme.titleLarge,
              3 => theme.textTheme.titleMedium,
              _ => theme.textTheme.titleSmall,
            }!).copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        MdParagraph() => rich(b.text, body),
        MdList() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var n = 0; n < b.items.length; n++)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(b.ordered ? '${n + 1}.' : '•', style: body),
                    ),
                    Expanded(child: rich(b.items[n], body)),
                  ],
                ),
              ),
          ],
        ),
        MdQuote() => Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: theme.colorScheme.outline, width: 3),
            ),
          ),
          child: rich(b.text, body.copyWith(fontStyle: FontStyle.italic)),
        ),
        MdCode() => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Text(b.text, style: body.copyWith(fontFamily: 'monospace')),
        ),
        MdRule() => const Divider(),
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in children)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: c),
      ],
    );
  }
}

const _markStart = '\u{E000}';
const _markEnd = '\u{E001}';

/// A search snippet with the matched words in bold. The server wraps them in U+E000 / U+E001.
List<TextSpan> snippetSpans(String snippet, TextStyle? base) {
  final spans = <TextSpan>[];
  var i = 0;
  while (i < snippet.length) {
    final s = snippet.indexOf(_markStart, i);
    if (s < 0) {
      spans.add(TextSpan(text: snippet.substring(i)));
      break;
    }
    if (s > i) spans.add(TextSpan(text: snippet.substring(i, s)));
    var e = snippet.indexOf(_markEnd, s);
    if (e < 0) e = snippet.length;
    spans.add(
      TextSpan(
        text: snippet.substring(s + 1, e),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
    i = e + 1;
  }
  return spans;
}

class HighlightedSnippet extends StatelessWidget {
  const HighlightedSnippet(this.snippet, {super.key, this.maxLines = 3});
  final String snippet;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodySmall;
    return Text.rich(
      TextSpan(style: base, children: snippetSpans(snippet, base)),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The snippet without the match markers, for places that show plain text.
String stripMarks(String snippet) =>
    snippet.replaceAll(_markStart, '').replaceAll(_markEnd, '');
