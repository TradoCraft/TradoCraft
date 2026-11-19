import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import 'decimal_expression.dart';
import 'format.dart';

/// Keeps the last confirmed number as the base for a relative edit.
class DecimalInputController extends TextEditingController {
  DecimalInputController({
    super.text,
    this.scale = 4,
    this.percentagePoints = false,
  }) {
    _currentValue = parseDecimalInput(text);
    focusNode.addListener(_commitOnBlur);
  }

  final int scale;
  final bool percentagePoints;
  final focusNode = FocusNode();
  String? _currentValue;

  /// The value to validate, preview or save, even while the field is focused.
  String? get decimal => evaluateDecimalInput(
    text,
    currentValue: _currentValue,
    scale: scale,
    percentagePoints: percentagePoints,
  );

  /// Programmatically loaded values (including an empty value) reset the base.
  @override
  set text(String newText) {
    _currentValue = parseDecimalInput(newText);
    super.text = newText;
  }

  @override
  void clear() {
    _currentValue = null;
    super.clear();
  }

  void _commitOnBlur() {
    if (focusNode.hasFocus) return;
    if (text.trim().isEmpty) {
      _currentValue = null;
      return;
    }
    final plain = parseDecimalInput(text);
    final result = plain ?? decimal;
    if (result == null) return;
    _currentValue = result;
    if (plain == null) {
      final display = result.replaceAll('.', ',');
      value = TextEditingValue(
        text: display,
        selection: TextSelection.collapsed(offset: display.length),
      );
    }
  }

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }
}

/// A decimal editor whose keyboard also exposes the characters used in formulas.
class DecimalField extends StatelessWidget {
  const DecimalField({
    super.key,
    required this.controller,
    this.fieldKey,
    this.decoration = const InputDecoration(),
    this.onChanged,
    this.onSubmitted,
    this.enabled,
    this.autofocus = false,
    this.style,
    this.textAlign = TextAlign.start,
  });

  final DecimalInputController controller;
  final Key? fieldKey;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool? enabled;
  final bool autofocus;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, controller.focusNode]),
    builder: (context, _) {
      final invalid =
          enabled != false &&
          !controller.focusNode.hasFocus &&
          controller.text.trim().isNotEmpty &&
          controller.decimal == null;
      return TextField(
        key: fieldKey,
        controller: controller,
        focusNode: controller.focusNode,
        enabled: enabled,
        autofocus: autofocus,
        decoration: invalid && decoration.errorText == null
            ? decoration.copyWith(errorText: context.l10n.cfgInvalidNumber)
            : decoration,
        style: style,
        textAlign: textAlign,
        autocorrect: false,
        enableSuggestions: false,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      );
    },
  );
}
