import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/api.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/app_icons.dart';
import 'draft.dart';

/// The functions of the formula language, for autocompletion.
final cfgFunctionsProvider = FutureProvider<List<Signature>>(
  (ref) => ref.watch(apiProvider).configurator.listFunctions(),
);

/// What a formula is written against: the definition being edited and the scope of the formula.
class FormulaContext {
  const FormulaContext(
    this.draft,
    this.scope, {
    this.inRule = false,
    this.locals = const [],
  });
  final DefinitionDraft draft;
  final ScopeSel scope;

  /// Extra local names, e.g. `p` (the product) in a product filter.
  final List<String> locals;

  /// Output rule formulas also see `each`, `each_index` and `parent`.
  final bool inRule;

  /// The local names sent with a live check: the rule locals only for output rules.
  List<String> get checkLocals => [
    ...locals,
    if (inRule) ...const ['each', 'each_index', 'parent'],
  ];

  String? get tableName {
    final t = scope.table;
    if (t == null) return null;
    final names = draft.itemTableNames();
    return t < names.length ? names[t] : null;
  }
}

/// A problem in a formula: a character range and a message.
typedef FormulaProblem = ({int start, int end, String message});

/// A text controller that draws formulas in a monospace font and underlines problem ranges.
class FormulaController extends TextEditingController {
  FormulaController({super.text});

  List<FormulaProblem> _problems = const [];
  List<FormulaProblem> get problems => _problems;
  set problems(List<FormulaProblem> p) {
    _problems = p;
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = (style ?? const TextStyle()).copyWith(fontFamily: 'monospace');
    if (_problems.isEmpty || text.isEmpty) {
      return TextSpan(style: base, text: text);
    }
    final error = Theme.of(context).colorScheme.error;
    final marked = List<bool>.filled(text.length, false);
    for (final p in _problems) {
      // An error at the very end (e.g. "1 +") marks the last character.
      var s = p.start.clamp(0, text.length);
      var e = p.end.clamp(0, text.length);
      if (s >= text.length) s = text.length - 1;
      if (e <= s) e = s + 1;
      for (var i = s; i < e && i < text.length; i++) {
        marked[i] = true;
      }
    }
    final spans = <TextSpan>[];
    var i = 0;
    while (i < text.length) {
      final m = marked[i];
      var j = i;
      while (j < text.length && marked[j] == m) {
        j++;
      }
      spans.add(
        TextSpan(
          text: text.substring(i, j),
          style: m
              ? TextStyle(
                  color: error,
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.wavy,
                  decorationColor: error,
                  backgroundColor: error.withValues(alpha: 0.12),
                )
              : null,
        ),
      );
      i = j;
    }
    return TextSpan(style: base, children: spans);
  }
}

/// A suggestion of the autocompletion.
class FormulaSuggestion {
  const FormulaSuggestion(this.name, this.kind, this.detail, {this.insert});
  final String name;
  final String kind;
  final String detail;

  /// The text inserted (defaults to [name]; functions get `name(`).
  final String? insert;
}

final _identChar = RegExp(r'[A-Za-z0-9_]');

/// The identifier being typed before [offset] in [text]: its start and prefix.
({int start, String prefix}) wordBefore(String text, int offset) {
  var s = offset.clamp(0, text.length);
  while (s > 0 && _identChar.hasMatch(text[s - 1])) {
    s--;
  }
  return (start: s, prefix: text.substring(s, offset.clamp(0, text.length)));
}

/// Whether [offset] is inside a `{...}` of a template.
bool insideTemplateExpr(String text, int offset) {
  var depth = 0;
  var inString = false;
  String? quote;
  for (var i = 0; i < offset && i < text.length; i++) {
    final ch = text[i];
    if (depth > 0 && (ch == "'" || ch == '"')) {
      if (!inString) {
        inString = true;
        quote = ch;
      } else if (ch == quote) {
        inString = false;
      }
    } else if (!inString && ch == '{') {
      depth++;
    } else if (!inString && ch == '}' && depth > 0) {
      depth--;
    }
  }
  return depth > 0;
}

/// Suggestions for [prefix]: names of the context first, then functions; matches by prefix
/// (case-insensitive), then by containment.
List<FormulaSuggestion> suggestionsFor(
  String prefix,
  List<NameHint> names,
  List<Signature> functions,
) {
  if (prefix.isEmpty) return const [];
  final p = prefix.toLowerCase();
  final all = [
    for (final n in names) FormulaSuggestion(n.name, n.kind, n.detail),
    for (final f in functions)
      FormulaSuggestion(f.name, 'function', f.usage, insert: '${f.name}('),
  ];
  final starts = [
    for (final s in all)
      if (s.name.toLowerCase().startsWith(p) && s.name != prefix) s,
  ];
  final contains = [
    for (final s in all)
      if (!s.name.toLowerCase().startsWith(p) &&
          s.name.toLowerCase().contains(p))
        s,
  ];
  return [...starts, ...contains].take(12).toList();
}

/// Edits a formula (or a `text {formula}` template): monospace, autocompletion of the names
/// the formula can use and of functions, and a live check on the server
/// (`POST /configurator/expressions/check`) that underlines the problem ranges.
class FormulaField extends ConsumerStatefulWidget {
  const FormulaField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.context,
    this.template = false,
    this.serverProblems = const [],
    this.hint,
    this.helper,
    this.enabled = true,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final FormulaContext context;

  /// Template mode: literal text with `{formula}` parts.
  final bool template;

  /// Problems the server reported for this property when the draft was saved; shown until the
  /// live check has run.
  final List<FormulaProblem> serverProblems;
  final String? hint;
  final String? helper;
  final bool enabled;
  final int maxLines;

  /// Pause after typing before the live check (shorter in tests).
  static Duration checkDelay = const Duration(milliseconds: 400);

  @override
  ConsumerState<FormulaField> createState() => _FormulaFieldState();
}

class _FormulaFieldState extends ConsumerState<FormulaField> {
  late final _controller = FormulaController(text: widget.value);
  final _focus = FocusNode();
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  Timer? _timer;
  int _seq = 0;
  String? _type;
  List<FormulaProblem>? _checked;
  bool _checking = false;
  List<FormulaSuggestion> _suggestions = const [];
  int _highlight = 0;

  @override
  void initState() {
    super.initState();
    _controller.problems = widget.serverProblems;
    _controller.addListener(_onEdit);
    _focus.addListener(() {
      if (!_focus.hasFocus) _hideSuggestions();
    });
  }

  @override
  void didUpdateWidget(FormulaField old) {
    super.didUpdateWidget(old);
    if (widget.value != _controller.text && !_focus.hasFocus) {
      _controller.text = widget.value;
      _checked = null;
      _type = null;
    }
    // A save that reports problems wins over an earlier live check (which cannot know, e.g., that
    // a validation's `when` must be a boolean), and a live check made in another scope or with
    // other locals no longer applies: check again.
    final serverChanged = !listEquals(
      old.serverProblems,
      widget.serverProblems,
    );
    final contextChanged =
        old.context.scope != widget.context.scope ||
        old.context.tableName != widget.context.tableName ||
        !listEquals(old.context.checkLocals, widget.context.checkLocals);
    if (serverChanged && widget.serverProblems.isNotEmpty) {
      _checked = null;
      _type = null;
    }
    if (contextChanged && _checked != null) {
      _checked = null;
      _type = null;
      _timer?.cancel();
      _timer = Timer(FormulaField.checkDelay, _check);
    }
    if (_checked == null && (serverChanged || contextChanged)) {
      _controller.problems = widget.serverProblems;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _lastText = '';

  void _onEdit() {
    final text = _controller.text;
    if (text != _lastText) {
      _lastText = text;
      if (text != widget.value) widget.onChanged(text);
      _timer?.cancel();
      _timer = Timer(FormulaField.checkDelay, _check);
    }
    _updateSuggestions();
  }

  Future<void> _check() async {
    final source = _controller.text;
    final seq = ++_seq;
    if (source.trim().isEmpty) {
      setState(() {
        _checked = const [];
        _type = null;
      });
      _controller.problems = const [];
      return;
    }
    setState(() => _checking = true);
    try {
      final r = await ref
          .read(apiProvider)
          .configurator
          .checkExpression(
            body: ExpressionCheckInput(
              source: source,
              template: widget.template,
              definition: widget.context.draft.toJson(),
              scope: RuleScope.fromJson(widget.context.scope.apiScope),
              table: widget.context.tableName,
              locals: widget.context.checkLocals.isEmpty
                  ? null
                  : widget.context.checkLocals,
            ),
          );
      if (!mounted || seq != _seq) return;
      final problems = [
        for (final e in r.errors)
          (start: e.start, end: e.end, message: e.message),
      ];
      setState(() {
        _checked = problems;
        _type = r.ok ? r.type : null;
        _checking = false;
      });
      _controller.problems = problems;
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _checking = false;
        _checked = [(start: 0, end: 0, message: errorMessage(e))];
        _type = null;
      });
      _controller.problems = const [];
    }
  }

  void _updateSuggestions() {
    if (!_focus.hasFocus) return;
    final sel = _controller.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      _hideSuggestions();
      return;
    }
    final text = _controller.text;
    if (widget.template && !insideTemplateExpr(text, sel.baseOffset)) {
      _hideSuggestions();
      return;
    }
    final w = wordBefore(text, sel.baseOffset);
    // After a dot (a record field) names of the scope do not apply.
    if (w.start > 0 && text[w.start - 1] == '.') {
      _hideSuggestions();
      return;
    }
    final functions = ref.read(cfgFunctionsProvider).value ?? const [];
    final s = suggestionsFor(w.prefix, [
      for (final l in widget.context.locals) NameHint(l, 'local'),
      ...widget.context.draft.namesFor(
        widget.context.scope,
        inRule: widget.context.inRule,
      ),
    ], functions);
    if (s.isEmpty) {
      _hideSuggestions();
      return;
    }
    setState(() {
      _suggestions = s;
      _highlight = 0;
    });
    _portal.show();
  }

  void _hideSuggestions() {
    if (_portal.isShowing) _portal.hide();
    if (_suggestions.isNotEmpty && mounted) {
      setState(() => _suggestions = const []);
    }
  }

  void _accept(FormulaSuggestion s) {
    final text = _controller.text;
    final offset = _controller.selection.baseOffset.clamp(0, text.length);
    final w = wordBefore(text, offset);
    final insert = s.insert ?? s.name;
    final next = text.replaceRange(w.start, offset, insert);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: w.start + insert.length),
    );
    _hideSuggestions();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (_suggestions.isEmpty || e is KeyUpEvent) return KeyEventResult.ignored;
    switch (e.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        setState(() => _highlight = (_highlight + 1) % _suggestions.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        setState(
          () => _highlight =
              (_highlight - 1 + _suggestions.length) % _suggestions.length,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.tab:
        _accept(_suggestions[_highlight]);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _hideSuggestions();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  IconData _icon(String kind) => switch (kind) {
    'function' => AppIcons.functions,
    'table' => AppIcons.tableChart,
    'items' => AppIcons.viewList,
    'computed' => AppIcons.calculate,
    'local' => AppIcons.label,
    _ => AppIcons.input,
  };

  @override
  Widget build(BuildContext context) {
    // Load the functions once; suggestions read them when typing.
    ref.watch(cfgFunctionsProvider);
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final problems = _checked ?? widget.serverProblems;
    final firstProblem = problems.isEmpty ? null : problems.first;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, -18),
          child: Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 440,
                  maxHeight: 280,
                ),
                child: ListView(
                  key: const ValueKey('formula-suggestions'),
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final (i, s) in _suggestions.indexed)
                      ListTile(
                        dense: true,
                        selected: i == _highlight,
                        leading: Icon(_icon(s.kind), size: 18),
                        title: Text(
                          s.name,
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                        subtitle: s.detail.isEmpty
                            ? null
                            : Text(
                                s.detail,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: () => _accept(s),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        child: Focus(
          onKeyEvent: _onKey,
          skipTraversal: true,
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            enabled: widget.enabled,
            minLines: 1,
            maxLines: widget.maxLines,
            style: const TextStyle(fontFamily: 'monospace'),
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint,
              isDense: true,
              helperText: firstProblem == null
                  ? (_type != null
                        ? l10n.cfgbFormulaType(_type!)
                        : widget.helper)
                  : null,
              errorText: firstProblem?.message,
              errorMaxLines: 3,
              prefixIcon: Icon(
                widget.template ? AppIcons.textFields : AppIcons.functions,
                size: 18,
              ),
              suffixIcon: _checking
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_checked != null && _checked!.isEmpty && _type != null)
                  ? Icon(
                      AppIcons.check,
                      size: 18,
                      color: theme.colorScheme.primary,
                    )
                  : null,
            ),
            onTap: _updateSuggestions,
          ),
        ),
      ),
    );
  }
}
