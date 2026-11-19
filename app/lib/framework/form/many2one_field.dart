import 'package:material_ui/material_ui.dart';

import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/search_picker.dart';

/// A field that links the record to one other record (a customer, a product), picked by a server
/// search (ADR 0085). Built on [SearchPicker].
///
/// The value only changes by picking an entry, the clear button or erasing the text; typing alone
/// does not. On validation the field is an error when [required] and empty, or when the text no
/// longer matches the picked entry ("choose from the list"), so a half-typed name is never saved
/// as if it were the old value.
class Many2OneField<T extends Object> extends StatefulWidget {
  const Many2OneField({
    super.key,
    required this.value,
    required this.label,
    required this.display,
    required this.search,
    required this.onChanged,
    this.idOf,
    this.required = false,
    this.readOnly = false,
    this.enabled = true,
    this.onOpen,
  });

  final T? value;
  final String label;
  final String Function(T) display;
  final Future<List<T>> Function(String query) search;

  /// Called with the picked entry, or null when cleared.
  final ValueChanged<T?> onChanged;

  /// A stable identity of an entry (its id). Without it a new instance of the same record (after a
  /// reload) rebuilds the field.
  final Object Function(T)? idOf;
  final bool required;

  /// Shows the value as text (with the open button) instead of an input.
  final bool readOnly;

  /// False while the form is busy: the field shows its value but takes no input.
  final bool enabled;

  /// Opens the linked record; adds an open button when set.
  final void Function(T value)? onOpen;

  @override
  State<Many2OneField<T>> createState() => _Many2OneFieldState<T>();
}

class _Many2OneFieldState<T extends Object> extends State<Many2OneField<T>> {
  Object? get _identity {
    final v = widget.value;
    if (v == null) return null;
    return widget.idOf?.call(v) ?? v;
  }

  String? _validate(String text) {
    final s = text.trim();
    final v = widget.value;
    if (s.isEmpty) return widget.required ? context.l10n.required : null;
    if (v == null || s != widget.display(v).trim()) {
      return context.l10n.formChooseFromList;
    }
    return null;
  }

  Widget? _openButton(T? v) {
    final open = widget.onOpen;
    if (v == null || open == null) return null;
    return IconButton(
      tooltip: context.l10n.formOpenRecord(widget.display(v)),
      icon: const Icon(AppIcons.openInNew, size: 18),
      onPressed: () => open(v),
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    if (widget.readOnly) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: widget.label,
          border: InputBorder.none,
          suffixIcon: _openButton(v),
        ),
        child: Text(v == null ? '—' : widget.display(v)),
      );
    }
    final open = _openButton(v);
    final clear = v == null || !widget.enabled
        ? null
        : IconButton(
            tooltip: context.l10n.formClearValue,
            icon: const Icon(AppIcons.close, size: 18),
            onPressed: () => widget.onChanged(null),
          );
    return SearchPicker<T>(
      // A new value (picked elsewhere, reloaded, cleared) shows its own text.
      key: ValueKey(_identity),
      label: widget.label,
      initial: v,
      display: widget.display,
      search: widget.search,
      enabled: widget.enabled,
      onSelected: widget.onChanged,
      onTextChanged: (text) {
        // Erasing the text clears the link.
        if (text.trim().isEmpty && widget.value != null) widget.onChanged(null);
      },
      validator: _validate,
      suffix: open == null && clear == null
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: [?open, ?clear]),
    );
  }
}
