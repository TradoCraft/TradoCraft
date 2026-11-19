import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';

/// Groups the digits of a decimal string for display.

String _grouped(String fixed) {
  final negative = fixed.startsWith('-');
  final digits = negative ? fixed.substring(1) : fixed;
  final parts = digits.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
    buf.write(intPart[i]);
  }
  final frac = parts.length > 1 ? ',${parts[1]}' : '';
  return '${negative ? '-' : ''}$buf$frac';
}

/// `1234.5` -> `1.234,50`
String money(String? value, {String currency = 'EUR'}) {
  if (value == null || value.isEmpty) return '';
  final d = Decimal.tryParse(value);
  if (d == null) return value;
  final symbol = currency == 'EUR' ? '€ ' : '$currency ';
  return '$symbol${_grouped(d.toStringAsFixed(2))}';
}

/// `2.5000` -> `2,5`
String number(String? value) {
  if (value == null || value.isEmpty) return '';
  final d = Decimal.tryParse(value);
  if (d == null) return value;
  var s = d.toString();
  return _grouped(s);
}

String date(DateTime? d) => d == null ? '' : DateFormat('dd/MM/yyyy').format(d);

/// A stored decimal for editing, with a decimal comma and no grouping.
String editableDecimal(String? value) =>
    parseDecimalInput(value ?? '')?.replaceAll('.', ',') ?? '';

/// Accepts `2,5` as well as `2.5`. Returns null if invalid.
String? parseDecimalInput(String text) {
  final normalized = text.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  final d = Decimal.tryParse(normalized);
  return d?.toString();
}
