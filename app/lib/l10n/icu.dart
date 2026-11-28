import 'package:intl/intl.dart' as intl;

/// Formats an ICU message the way gen-l10n does for the shipped ARB files, for messages that
/// arrive at runtime (ADR 0101): `{name}` placeholders, `{n, plural, =0{..} one{..} other{..}}`
/// (with `#` for the number and the plural rules of [locale]) and `{x, select, a{..} other{..}}`.
/// Throws [FormatException] on a malformed message.
String formatIcu(String message, Map<String, Object?> args, String locale) {
  final p = _Parser(message);
  final nodes = p.parseNodes(topLevel: true);
  return _render(nodes, args, locale, null);
}

/// Whether [message] is a well-formed ICU message (for checking an uploaded catalogue).
bool isValidIcu(String message) {
  try {
    _Parser(message).parseNodes(topLevel: true);
    return true;
  } on FormatException {
    return false;
  }
}

sealed class _Node {}

class _Text extends _Node {
  _Text(this.text);
  final String text;
}

/// `#` inside a plural branch.
class _Hash extends _Node {}

class _Arg extends _Node {
  _Arg(this.name, this.kind, this.branches);
  final String name;

  /// null (plain placeholder), `plural` or `select`.
  final String? kind;
  final Map<String, List<_Node>> branches;
}

class _Parser {
  _Parser(this.s);
  final String s;
  int i = 0;

  FormatException _error(String what) =>
      FormatException('$what at $i in "$s"');

  List<_Node> parseNodes({required bool topLevel, bool inPlural = false}) {
    final out = <_Node>[];
    final text = StringBuffer();
    void flush() {
      if (text.isNotEmpty) {
        out.add(_Text(text.toString()));
        text.clear();
      }
    }

    while (i < s.length) {
      final c = s[i];
      if (c == '{') {
        flush();
        out.add(_parseArg());
      } else if (c == '}') {
        if (topLevel) throw _error('unexpected }');
        break;
      } else if (c == '#' && inPlural) {
        flush();
        out.add(_Hash());
        i++;
      } else {
        text.write(c);
        i++;
      }
    }
    flush();
    return out;
  }

  void _skipSpace() {
    while (i < s.length && s[i].trim().isEmpty) {
      i++;
    }
  }

  String _word() {
    _skipSpace();
    final start = i;
    while (i < s.length && !',{}'.contains(s[i]) && s[i].trim().isNotEmpty) {
      i++;
    }
    if (start == i) throw _error('name expected');
    return s.substring(start, i);
  }

  _Arg _parseArg() {
    i++; // {
    final name = _word();
    _skipSpace();
    if (i >= s.length) throw _error('unclosed {');
    if (s[i] == '}') {
      i++;
      return _Arg(name, null, const {});
    }
    if (s[i] != ',') throw _error(', expected');
    i++;
    final kind = _word();
    if (kind != 'plural' && kind != 'select') throw _error('unknown kind $kind');
    _skipSpace();
    if (i >= s.length || s[i] != ',') throw _error(', expected');
    i++;
    final branches = <String, List<_Node>>{};
    while (true) {
      _skipSpace();
      if (i >= s.length) throw _error('unclosed {');
      if (s[i] == '}') {
        i++;
        break;
      }
      final key = _word();
      _skipSpace();
      if (i >= s.length || s[i] != '{') throw _error('{ expected');
      i++;
      branches[key] = parseNodes(topLevel: false, inPlural: kind == 'plural');
      if (i >= s.length || s[i] != '}') throw _error('} expected');
      i++;
    }
    if (!branches.containsKey('other')) throw _error('other branch missing');
    return _Arg(name, kind, branches);
  }
}

String _render(
  List<_Node> nodes,
  Map<String, Object?> args,
  String locale,
  num? hash,
) {
  final out = StringBuffer();
  for (final n in nodes) {
    switch (n) {
      case _Text(:final text):
        out.write(text);
      case _Hash():
        out.write(hash ?? '#');
      case _Arg(:final name, kind: null):
        out.write(args.containsKey(name) ? '${args[name]}' : '{$name}');
      case _Arg(:final name, kind: 'plural', :final branches):
        final value = args[name];
        final n = value is num ? value : num.tryParse('$value') ?? 0;
        final exact = branches['=$n'];
        final branch =
            exact ??
            intl.Intl.pluralLogic<List<_Node>>(
              n,
              locale: locale,
              zero: branches['zero'],
              one: branches['one'],
              two: branches['two'],
              few: branches['few'],
              many: branches['many'],
              other: branches['other']!,
            );
        out.write(_render(branch, args, locale, n));
      case _Arg(:final name, :final branches):
        final branch = branches['${args[name]}'] ?? branches['other']!;
        out.write(_render(branch, args, locale, hash));
    }
  }
  return out.toString();
}
