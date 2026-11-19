import 'package:decimal/decimal.dart';
import 'package:rational/rational.dart';

import 'format.dart';

/// Evaluates a calculation for an editable decimal field. The result is rounded
/// once, to the field's precision. Plain numbers retain their entered precision.
String? evaluateDecimalInput(
  String text, {
  String? currentValue,
  int scale = 4,
  bool percentagePoints = false,
}) {
  final plain = parseDecimalInput(text);
  if (plain != null) return plain;
  final input = text.replaceAll(RegExp(r'\s+'), '').replaceAll(',', '.');
  if (input.isEmpty || input.length > 256) return null;

  final adjustment = RegExp(r'^[+*/-]=').hasMatch(input);
  final start = adjustment ? 2 : (input.startsWith('=') ? 1 : 0);
  final parser = _DecimalExpression(input, start, percentagePoints);
  try {
    var result = parser.sum();
    if (!parser.atEnd) return null;
    if (adjustment) {
      if (currentValue == null) return null;
      result = _calculate(
        (value: Rational.parse(currentValue), percent: false),
        input[0],
        result,
      );
    }
    final value = percentagePoints && result.percent
        ? result.value * _hundred
        : result.value;
    final shifted = value * Rational(BigInt.from(10).pow(scale));
    return Decimal.fromBigInt(shifted.round()).shift(-scale).toString();
  } on FormatException {
    return null;
  }
}

typedef _Operand = ({Rational value, bool percent});

final _hundred = Rational.fromInt(100);

_Operand _calculate(
  _Operand left,
  String operator,
  _Operand right, {
  bool keepRates = false,
}) {
  final a = left.value;
  var b = right.value;
  final additive = operator == '+' || operator == '-';
  // 200 + 10% adds 10% of 200. Two rate literals add as rates.
  if (additive && right.percent && !left.percent) b = a * b;
  if (operator == '/' && b.numerator == BigInt.zero) {
    throw const FormatException('Division by zero');
  }
  final value = switch (operator) {
    '+' => a + b,
    '-' => a - b,
    '*' => a * b,
    '/' => a / b,
    _ => throw StateError('Unknown arithmetic operator'),
  };
  // A percentage field displays a rate such as 10% * 2 as 20 percentage
  // points. An adjustment applies the factor directly to the existing number.
  final percent = switch (operator) {
    '+' || '-' => left.percent && right.percent,
    '*' => keepRates && (left.percent || right.percent),
    '/' => keepRates && left.percent && !right.percent,
    _ => false,
  };
  return (value: value, percent: percent);
}

class _DecimalExpression {
  _DecimalExpression(this.input, this.position, this.keepRates);

  static final _number = RegExp(r'(?:\d+(?:\.\d*)?|\.\d+)');

  final String input;
  final bool keepRates;
  int position;

  bool get atEnd => position == input.length;

  bool _take(String token) {
    if (!input.startsWith(token, position)) return false;
    position++;
    return true;
  }

  _Operand sum() {
    var result = _product();
    while (_take('+') || _take('-')) {
      final operator = input[position - 1];
      result = _calculate(result, operator, _product());
    }
    return result;
  }

  _Operand _product() {
    var result = _signed();
    while (_take('*') || _take('/')) {
      final operator = input[position - 1];
      result = _calculate(result, operator, _signed(), keepRates: keepRates);
    }
    return result;
  }

  _Operand _signed() {
    if (_take('+')) return _signed();
    if (_take('-')) {
      final operand = _signed();
      return (value: -operand.value, percent: operand.percent);
    }
    final operand = _primary();
    if (!_take('%')) return operand;
    if (operand.percent) throw const FormatException('Repeated percent sign');
    return (value: operand.value / _hundred, percent: true);
  }

  _Operand _primary() {
    if (_take('(')) {
      final operand = sum();
      if (!_take(')')) {
        throw const FormatException('Missing closing parenthesis');
      }
      return operand;
    }
    final match = _number.matchAsPrefix(input, position);
    if (match == null) throw const FormatException('Expected a number');
    position = match.end;
    return (value: Decimal.parse(match[0]!).toRational(), percent: false);
  }
}
