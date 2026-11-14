import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../app/api.dart';
import '../../../l10n/l10n.dart';
import '../../../shared/app_icons.dart';
import '../../../shared/format.dart';
import '../definition.dart';
import '../runner_state.dart';

/// Everything a field widget needs to render one place of the configuration.
class RunnerView {
  const RunnerView({
    required this.definition,
    required this.inputs,
    required this.index,
    required this.actions,
    this.displayUnits = const {},
    this.focus,
  });

  final CfgDefinition definition;
  final RunnerInputs inputs;
  final EvalIndex index;
  final RunnerActions actions;
  final Map<String, String> displayUnits;
  final FieldFocus? focus;

  /// Display unit key of a field: `name` (project), `group.name` or `table.name`.
  static String unitKey(FieldRef ref) => ref.table != null
      ? '${ref.table}.${ref.name}'
      : ref.group != null
      ? 'group.${ref.name}'
      : ref.name;

  String displayUnit(FieldRef ref, CfgField f) {
    final u = displayUnits[unitKey(ref)];
    return (u != null && f.inputUnits.contains(u)) ? u : (f.unit ?? '');
  }
}

/// Focus nodes and keys per field, so the issues panel can bring a field into view.
class FieldFocus {
  final _nodes = <String, FocusNode>{};
  final _keys = <String, GlobalKey>{};

  FocusNode node(FieldRef ref) => _nodes.putIfAbsent(ref.key, FocusNode.new);
  GlobalKey keyOf(FieldRef ref) => _keys.putIfAbsent(ref.key, GlobalKey.new);

  /// Scrolls the field into view and focuses it; false when it is not on screen.
  bool focus(FieldRef ref) {
    final ctx = _keys[ref.key]?.currentContext;
    if (ctx == null) return false;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 250),
      alignment: 0.3,
    );
    _nodes[ref.key]?.requestFocus();
    return true;
  }

  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
  }
}

String _lang(BuildContext context) =>
    Localizations.localeOf(context).languageCode;

/// A value with its unit, as text.
String valueWithUnit(Object? v, String? unit) {
  final s = displayValue(v);
  if (s.isEmpty || unit == null || unit.isEmpty) return s;
  return '$s $unit';
}

String? _errorText(List<Issue> issues) {
  for (final i in issues) {
    if (i.severity == IssueSeverity.error) return i.message;
  }
  return null;
}

/// One input or computed value of the definition at [ref]: the right widget for its type.
class ConfigEntryWidget extends StatelessWidget {
  const ConfigEntryWidget({
    super.key,
    required this.view,
    required this.entry,
    required this.ref,
    this.dense = false,
  });

  final RunnerView view;
  final CfgEntry entry;
  final FieldRef ref;

  /// Compact cell for the item grid: no label or help.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final result = view.index[ref];
    final child = switch (entry) {
      CfgField f => ConfigFieldInput(
        field: f,
        result: result,
        input: view.inputs.valueOf(ref),
        issues: view.index.issuesAt(ref),
        dense: dense,
        displayUnit: view.displayUnit(ref, f),
        onUnit: (u) => view.actions.setDisplayUnit(RunnerView.unitKey(ref), u),
        onChanged: (v) => view.actions.setValue(ref, v),
        focusNode: view.focus?.node(ref),
      ),
      CfgComputed c => ComputedValueView(
        computed: c,
        result: result,
        issues: view.index.issuesAt(ref),
        dense: dense,
        onPin: (v) => view.actions.pin(ref, v),
        onUnpin: () => view.actions.unpin(ref),
        focusNode: view.focus?.node(ref),
      ),
    };
    final focus = view.focus;
    return focus == null
        ? child
        : KeyedSubtree(key: focus.keyOf(ref), child: child);
  }
}

/// The input of one field. [input] is what the user entered (null: nothing, the default or
/// calculation applies); [result] is the field's evaluation (visibility, enabled, options, the
/// effective value).
class ConfigFieldInput extends StatelessWidget {
  const ConfigFieldInput({
    super.key,
    required this.field,
    required this.result,
    required this.input,
    required this.onChanged,
    this.issues = const [],
    this.dense = false,
    this.displayUnit,
    this.onUnit,
    this.focusNode,
  });

  final CfgField field;
  final ValueResult? result;
  final Object? input;
  final ValueChanged<Object?> onChanged;
  final List<Issue> issues;
  final bool dense;
  final String? displayUnit;
  final ValueChanged<String>? onUnit;
  final FocusNode? focusNode;

  bool get visible => result?.visible ?? true;
  bool get enabled => result?.enabled ?? true;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return dense ? const _HiddenCell() : const SizedBox.shrink();
    }
    final lang = _lang(context);
    final label = '${field.labelIn(lang)}${field.required ? ' *' : ''}';
    final help = field.helpIn(lang);
    final error = _errorText(issues);
    // The effective value (default, or the project value a group field falls back to) when the
    // user entered nothing: shown as a hint.
    final effective = input ?? result?.value;
    switch (field.type) {
      case CfgFieldType.boolean:
        final value = effective == true || effective == 'true';
        final box = Checkbox(
          value: value,
          focusNode: focusNode,
          onChanged: enabled ? (v) => onChanged(v ?? false) : null,
        );
        if (dense) return Align(alignment: Alignment.centerLeft, child: box);
        return Tooltip(
          message: help,
          child: InkWell(
            onTap: enabled ? () => onChanged(!value) : null,
            child: InputDecorator(
              decoration: InputDecoration(
                border: InputBorder.none,
                errorText: error,
                isDense: true,
              ),
              child: Row(
                children: [
                  box,
                  Flexible(child: Text(label)),
                ],
              ),
            ),
          ),
        );
      case CfgFieldType.choice:
        return _ChoiceInput(
          field: field,
          options: result?.options ?? [for (final o in field.options) o.value],
          value: effective,
          hasInput: input != null,
          label: dense ? null : label,
          help: dense ? null : help,
          error: error,
          enabled: enabled,
          focusNode: focusNode,
          onChanged: onChanged,
        );
      case CfgFieldType.number:
      case CfgFieldType.integer:
        final unit = field.unit;
        final shown = displayUnit ?? unit ?? '';
        String? conv(Object? v) {
          if (v == null) return null;
          final s = displayValue(v);
          return unit == null
              ? s
              : convertUnit(s, field.dimension, unit, shown);
        }

        final range = [
          if (field.min != null || field.max != null)
            '${conv(field.min) ?? ''} – ${conv(field.max) ?? ''} $shown'.trim(),
        ];
        return _TextInput(
          text: conv(input) ?? '',
          hint: input == null ? conv(result?.value) : null,
          label: dense ? null : label,
          help: dense
              ? null
              : [help, ...range].where((s) => s.isNotEmpty).join(' · '),
          error: error,
          enabled: enabled,
          numeric: true,
          integer: field.type == CfgFieldType.integer,
          focusNode: focusNode,
          suffix: field.inputUnits.length > 1 && !dense && onUnit != null
              ? _UnitPicker(
                  units: field.inputUnits,
                  unit: shown,
                  onChanged: onUnit!,
                )
              : (shown.isEmpty || dense ? null : Text(shown)),
          onChanged: (text) {
            if (text.isEmpty) return onChanged(null);
            final parsed = parseDecimalInput(text);
            if (parsed == null) return;
            if (field.type == CfgFieldType.integer) {
              final i = int.tryParse(parsed);
              if (i != null) onChanged(i);
              return;
            }
            onChanged(
              unit == null
                  ? parsed
                  : convertUnit(parsed, field.dimension, shown, unit),
            );
          },
        );
      case CfgFieldType.text:
      case CfgFieldType.product:
        return _TextInput(
          text: input == null ? '' : displayValue(input),
          hint: input == null ? displayValue(result?.value) : null,
          label: dense ? null : label,
          help: dense ? null : help,
          error: error,
          enabled: enabled,
          maxLength: field.maxLength,
          focusNode: focusNode,
          suggestions: field.type == CfgFieldType.product
              ? [for (final o in result?.options ?? const []) '$o']
              : null,
          prefix: field.type == CfgFieldType.product && !dense
              ? const Icon(AppIcons.inventory2, size: 18)
              : null,
          onChanged: (t) => onChanged(t.trim().isEmpty ? null : t),
        );
    }
  }
}

class _HiddenCell extends StatelessWidget {
  const _HiddenCell();

  @override
  Widget build(BuildContext context) =>
      Text('—', style: TextStyle(color: Theme.of(context).colorScheme.outline));
}

class _UnitPicker extends StatelessWidget {
  const _UnitPicker({
    required this.units,
    required this.unit,
    required this.onChanged,
  });

  final List<String> units;
  final String unit;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonHideUnderline(
    child: DropdownButton<String>(
      value: units.contains(unit) ? unit : units.first,
      isDense: true,
      items: [
        for (final u in units) DropdownMenuItem(value: u, child: Text(u)),
      ],
      onChanged: (u) {
        if (u != null) onChanged(u);
      },
    ),
  );
}

/// Picks one of a choice field's options; "—" clears the input so the default applies.
class _ChoiceInput extends StatelessWidget {
  const _ChoiceInput({
    required this.field,
    required this.options,
    required this.value,
    required this.hasInput,
    required this.label,
    required this.help,
    required this.error,
    required this.enabled,
    required this.onChanged,
    this.focusNode,
  });

  final CfgField field;
  final List<Object?> options;
  final Object? value;
  final bool hasInput;
  final String? label;
  final String? help;
  final String? error;
  final bool enabled;
  final ValueChanged<Object?> onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final lang = _lang(context);
    var selected = -1;
    for (var i = 0; i < options.length; i++) {
      if (sameValue(options[i], value)) selected = i;
    }
    final items = <DropdownMenuItem<int>>[
      if (!field.required || hasInput)
        const DropdownMenuItem(value: -1, child: Text('—')),
      for (final (i, o) in options.indexed)
        DropdownMenuItem(
          value: i,
          child: Text(
            field.optionLabel(o, lang),
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];
    if (selected < 0 && !items.any((it) => it.value == -1)) {
      items.insert(0, const DropdownMenuItem(value: -1, child: Text('—')));
    }
    final dense = label == null;
    return DropdownButtonFormField<int>(
      key: ValueKey('choice-${field.name}-$selected-${options.length}'),
      initialValue: selected,
      isExpanded: true,
      isDense: dense,
      focusNode: focusNode,
      decoration: InputDecoration(
        labelText: label,
        helperText: (help?.isEmpty ?? true) ? null : help,
        errorText: dense ? null : error,
        isDense: dense,
        border: dense ? InputBorder.none : null,
        // Values the user did not choose (defaults) are shown lighter.
        hintText: dense ? null : null,
      ),
      style: hasInput
          ? null
          : Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      items: items,
      onChanged: enabled
          ? (i) => onChanged(i == null || i < 0 ? null : options[i])
          : null,
    );
  }
}

/// A text or number box that keeps the user's typing while new evaluations arrive: the text is
/// only replaced from outside when the box does not have focus.
class _TextInput extends StatefulWidget {
  const _TextInput({
    required this.text,
    required this.onChanged,
    this.hint,
    this.label,
    this.help,
    this.error,
    this.enabled = true,
    this.numeric = false,
    this.integer = false,
    this.maxLength,
    this.suffix,
    this.prefix,
    this.suggestions,
    this.focusNode,
  });

  final String text;
  final String? hint;
  final String? label;
  final String? help;
  final String? error;
  final bool enabled;
  final bool numeric;
  final bool integer;
  final int? maxLength;
  final Widget? suffix;
  final Widget? prefix;

  /// Values offered while typing (product codes).
  final List<String>? suggestions;
  final FocusNode? focusNode;
  final ValueChanged<String> onChanged;

  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  late final _controller = TextEditingController(text: widget.text);
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());
  bool _invalid = false;

  @override
  void didUpdateWidget(_TextInput old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.text != _controller.text) {
      final typed = widget.numeric ? parseDecimalInput(_controller.text) : null;
      // `2,50` typed is still `2.5` from the server: keep the user's spelling.
      if (typed == null || typed != parseDecimalInput(widget.text)) {
        _controller.text = widget.text;
        _invalid = false;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _changed(String t) {
    if (widget.numeric && t.trim().isNotEmpty) {
      final p = parseDecimalInput(t);
      final bad = p == null || (widget.integer && int.tryParse(p) == null);
      if (bad != _invalid) setState(() => _invalid = bad);
      if (bad) return;
    } else if (_invalid) {
      setState(() => _invalid = false);
    }
    widget.onChanged(t);
  }

  @override
  Widget build(BuildContext context) {
    final dense = widget.label == null;
    final errorText = _invalid ? context.l10n.cfgInvalidNumber : widget.error;
    final Widget field = TextField(
      controller: _controller,
      focusNode: _focus,
      enabled: widget.enabled,
      keyboardType: widget.numeric
          ? TextInputType.numberWithOptions(
              decimal: !widget.integer,
              signed: true,
            )
          : TextInputType.text,
      maxLength: dense ? null : widget.maxLength,
      textAlign: widget.numeric && dense ? TextAlign.end : TextAlign.start,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        // Defaults and fallbacks are lighter than what the user typed.
        hintStyle: TextStyle(color: Theme.of(context).colorScheme.outline),
        // Keep the label up so the default (the hint) is visible without focus.
        floatingLabelBehavior: (widget.hint?.isNotEmpty ?? false)
            ? FloatingLabelBehavior.always
            : null,
        helperText: (widget.help?.isEmpty ?? true) ? null : widget.help,
        helperMaxLines: 2,
        // In a grid cell the message would not fit: a red underline and a tooltip instead.
        errorText: dense ? null : errorText,
        error: dense && errorText != null ? const SizedBox.shrink() : null,
        errorBorder: dense
            ? UnderlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error,
                  width: 2,
                ),
              )
            : null,
        isDense: dense,
        border: dense ? InputBorder.none : null,
        suffixIcon: widget.suffix == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 8),
                child: widget.suffix,
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        prefixIcon: widget.prefix,
        counterText: '',
      ),
      onChanged: _changed,
    );
    final suggestions = widget.suggestions;
    if (suggestions == null || suggestions.isEmpty) {
      return dense && errorText != null
          ? Tooltip(message: errorText, child: field)
          : field;
    }
    return RawAutocomplete<String>(
      textEditingController: _controller,
      focusNode: _focus,
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        return suggestions.where(
          (s) => q.isEmpty || s.toLowerCase().contains(q),
        );
      },
      onSelected: _changed,
      fieldViewBuilder: (_, _, _, _) => field,
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final o in options)
                  ListTile(
                    dense: true,
                    title: Text(o),
                    onTap: () => onSelected(o),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A computed value: read-only and in italics with a marker when calculated; in bold with
/// "reset to calculated" when pinned; with a warning when the pin is stale. Overridable values
/// offer their allowed alternatives to pin.
class ComputedValueView extends StatelessWidget {
  const ComputedValueView({
    super.key,
    required this.computed,
    required this.result,
    required this.onPin,
    required this.onUnpin,
    this.issues = const [],
    this.dense = false,
    this.focusNode,
  });

  final CfgComputed computed;
  final ValueResult? result;
  final ValueChanged<Object?> onPin;
  final VoidCallback onUnpin;
  final List<Issue> issues;
  final bool dense;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final lang = _lang(context);
    final r = result;
    final source = r?.source;
    final pinned = source == ValueSource.pinned || source == ValueSource.stale;
    final stale = source == ValueSource.stale;
    final failed = source == ValueSource.error;
    final unit = computed.unit;
    final style = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontStyle: pinned ? FontStyle.normal : FontStyle.italic,
      fontWeight: pinned ? FontWeight.bold : null,
      color: failed
          ? theme.colorScheme.error
          : stale
          ? Colors.orange.shade800
          : null,
    );
    final text = failed ? '!' : valueWithUnit(r?.value, unit);
    final options = r?.options;
    final canPick =
        computed.overridable && options != null && options.isNotEmpty;

    Widget value;
    if (canPick) {
      var selected = -1;
      for (var i = 0; i < options.length; i++) {
        if (sameValue(options[i], r?.value)) selected = i;
      }
      value = DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          key: ValueKey('pin-${computed.name}-$selected-${r?.source}'),
          value: selected < 0 ? null : selected,
          hint: Text(text, style: style),
          isDense: true,
          isExpanded: true,
          focusNode: focusNode,
          style: style.copyWith(
            color: style.color ?? theme.colorScheme.onSurface,
          ),
          items: [
            for (final (i, o) in options.indexed)
              DropdownMenuItem(
                value: i,
                child: Text(
                  valueWithUnit(o, unit),
                  overflow: TextOverflow.ellipsis,
                  style: sameValue(o, pinned ? r?.calculated : r?.value)
                      ? const TextStyle(fontStyle: FontStyle.italic)
                      : const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
          ],
          onChanged: (i) {
            if (i != null) onPin(options[i]);
          },
        ),
      );
    } else if (computed.overridable) {
      value = InkWell(
        focusNode: focusNode,
        onTap: () async {
          final controller = TextEditingController(
            text: displayValue(r?.value),
          );
          final v = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(computed.labelIn(lang)),
              content: TextField(controller: controller, autofocus: true),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, controller.text.trim()),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          if (v != null && v.isNotEmpty) onPin(v);
        },
        child: Text(text, style: style, overflow: TextOverflow.ellipsis),
      );
    } else {
      value = Focus(
        focusNode: focusNode,
        child: Text(text, style: style, overflow: TextOverflow.ellipsis),
      );
    }

    final marker = Tooltip(
      message: pinned
          ? stale
                ? l10n.cfgStale(valueWithUnit(r?.calculated, unit))
                : l10n.cfgPinned
          : failed
          ? (issues.isEmpty ? l10n.cfgCalculated : issues.first.message)
          : l10n.cfgCalculated,
      child: Icon(
        stale
            ? AppIcons.warningAmber
            : pinned
            ? AppIcons.pushPin
            : failed
            ? AppIcons.error
            : AppIcons.functions,
        size: 16,
        color: stale
            ? Colors.orange.shade800
            : failed
            ? theme.colorScheme.error
            : theme.colorScheme.outline,
      ),
    );
    final row = Row(
      children: [
        marker,
        const SizedBox(width: 6),
        Expanded(child: value),
        if (pinned)
          IconButton(
            tooltip: l10n.cfgResetToCalculated(
              valueWithUnit(r?.calculated, unit),
            ),
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            icon: const Icon(AppIcons.undo),
            onPressed: onUnpin,
          ),
      ],
    );
    if (dense) return row;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: computed.labelIn(lang),
        helperText: stale
            ? l10n.cfgStale(valueWithUnit(r?.calculated, unit))
            : (computed.helpIn(lang).isEmpty ? null : computed.helpIn(lang)),
        helperStyle: stale ? TextStyle(color: Colors.orange.shade800) : null,
        border: InputBorder.none,
        isDense: true,
      ),
      child: row,
    );
  }
}

/// The fields and computed values of one scope instance (the project, or one group) as a
/// responsive form, in the definition's layout sections.
class ConfigForm extends StatelessWidget {
  const ConfigForm({
    super.key,
    required this.view,
    required this.scope,
    required this.refOf,
    this.sections = const [],
  });

  final RunnerView view;
  final CfgScope scope;
  final FieldRef Function(String name) refOf;
  final List<CfgSection> sections;

  @override
  Widget build(BuildContext context) {
    final lang = _lang(context);
    final entries = <CfgEntry>[
      ...scope.fields,
      ...scope.computed.where((c) => c.show),
    ];
    final bySection = <String?, List<CfgEntry>>{};
    for (final e in entries) {
      final known = sections.any((s) => s.name == e.section);
      (bySection[known ? e.section : null] ??= []).add(e);
    }
    for (final MapEntry(:key, :value) in bySection.entries.toList()) {
      bySection[key] = byLayoutOrder(value);
    }
    final theme = Theme.of(context);
    final ordered = <(String?, List<CfgEntry>)>[
      if (bySection[null] != null) (null, bySection[null]!),
      for (final s in sections)
        if (bySection[s.name] != null) (s.labelIn(lang), bySection[s.name]!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (title, list) in ordered) ...[
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Text(title, style: theme.textTheme.titleSmall),
            ),
          _section([
            for (final e in list)
              if (view.index[refOf(e.name)]?.visible ?? true) e,
          ]),
        ],
      ],
    );
  }

  /// The entries of one section: in the designer's columns (`layout.column`) when there is room
  /// for them, else wrapped by order and width.
  Widget _section(List<CfgEntry> shown) {
    Widget entry(CfgEntry e) =>
        ConfigEntryWidget(view: view, entry: e, ref: refOf(e.name));
    final wrap = Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final e in shown)
          SizedBox(width: 280.0 * e.width.clamp(1, 3), child: entry(e)),
      ],
    );
    final columns = shown.fold(
      0,
      (n, e) => math.max(n, (e.column ?? 1).clamp(1, 4)),
    );
    if (columns < 2) return wrap;
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < columns * 280 + (columns - 1) * 16) return wrap;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var k = 1; k <= columns; k++) ...[
              if (k > 1) const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final e in shown)
                      if ((e.column ?? 1).clamp(1, 4) == k)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: entry(e),
                        ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
