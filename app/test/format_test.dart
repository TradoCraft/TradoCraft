import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/shared/decimal_expression.dart';
import 'package:tradocraft_app/shared/format.dart';

void main() {
  test('money uses Belgian notation', () {
    expect(money('1234.5'), '€ 1.234,50');
    expect(money('0'), '€ 0,00');
    expect(money('1234567.891'), '€ 1.234.567,89');
    expect(money('-12.3', currency: 'USD'), 'USD -12,30');
    expect(money(null), '');
  });

  test('number drops trailing zeros', () {
    expect(number('2.0000'), '2');
    expect(number('12.5000'), '12,5');
    expect(number('1000'), '1.000');
  });

  test('decimal input accepts comma and dot', () {
    expect(parseDecimalInput('2,5'), '2.5');
    expect(parseDecimalInput(' 10 '), '10');
    expect(parseDecimalInput('abc'), isNull);
    expect(parseDecimalInput(''), isNull);
    expect(editableDecimal('1234.5000'), '1234,5');
  });

  test('evaluates signed arithmetic and rounds only the result', () {
    expect(evaluateDecimalInput('=(12 + 3) * 4,50'), '67.5');
    expect(evaluateDecimalInput('2 - -3 * 4'), '14');
    expect(evaluateDecimalInput('1 / 3 * 3'), '1');
    expect(evaluateDecimalInput('-1 / 6', scale: 2), '-0.17');
    expect(evaluateDecimalInput('1.23456'), '1.23456');
  });

  test('uses percentage operands for rates and relative changes', () {
    expect(evaluateDecimalInput('250 * 10%'), '25');
    expect(evaluateDecimalInput('250 - 10%'), '225');
    expect(evaluateDecimalInput('250 + 10%'), '275');
    expect(evaluateDecimalInput('121 / (1 + 21%)'), '100');
    expect(evaluateDecimalInput('-10%', percentagePoints: true), '-10');
    expect(evaluateDecimalInput('5% + 2%', percentagePoints: true), '7');
    expect(evaluateDecimalInput('10% * 2', percentagePoints: true), '20');
    expect(evaluateDecimalInput('10% / 2', percentagePoints: true), '5');
    expect(
      evaluateDecimalInput('*=10%', currentValue: '20', percentagePoints: true),
      '2',
    );
    expect(evaluateDecimalInput('+=10%', currentValue: '250'), '275');
    expect(evaluateDecimalInput('-=5', currentValue: '250'), '245');
    expect(evaluateDecimalInput('*=1,10', currentValue: '250'), '275');
    expect(evaluateDecimalInput('/=(2 + 3)', currentValue: '250'), '50');
  });

  test('rejects an invalid expression instead of committing a value', () {
    for (final input in ['1/0', '2 +', '(2 * 3', '2(3)', '10%%', '+=2']) {
      expect(evaluateDecimalInput(input), isNull, reason: input);
    }
  });
}
