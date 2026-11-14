import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/features/products/voltage_range.dart';

void main() {
  VoltageRangeCheck check(String min, String max, {int nominal = 230}) =>
      checkVoltageRange(nominal: nominal, min: min, max: max);

  test('both empty means no explicit bounds', () {
    final c = check('', '  ');
    expect(c.error, isNull);
    expect(c.min, isNull);
    expect(c.max, isNull);
  });

  test('a valid pair is parsed', () {
    final c = check('200', '250');
    expect(c.error, isNull);
    expect((c.min, c.max), (200, 250));
  });

  test('the nominal voltage may sit on a bound', () {
    expect(check('230', '250').error, isNull);
    expect(check('200', '230').error, isNull);
  });

  test('only one bound is refused', () {
    expect(check('200', '').error, VoltageRangeError.incomplete);
    expect(check('', '250').error, VoltageRangeError.incomplete);
  });

  test('bounds must be whole numbers from 1 to 100000', () {
    expect(check('0', '250').error, VoltageRangeError.invalid);
    expect(check('-5', '250').error, VoltageRangeError.invalid);
    expect(check('a', '250').error, VoltageRangeError.invalid);
    expect(check('200', '100001').error, VoltageRangeError.invalid);
  });

  test('min must not exceed max', () {
    expect(check('260', '250', nominal: 255).error, VoltageRangeError.order);
  });

  test('the nominal voltage must lie within the bounds', () {
    expect(check('100', '120').error, VoltageRangeError.nominalOutside);
    expect(check('240', '250').error, VoltageRangeError.nominalOutside);
  });
}
