/// Why an explicit voltage range was refused. Mirrors the server rules for
/// `voltage_min_v` / `voltage_max_v` on a power supply.
enum VoltageRangeError { incomplete, invalid, order, nominalOutside }

/// The outcome of [checkVoltageRange]: parsed bounds (both null = no explicit range) or an error.
class VoltageRangeCheck {
  const VoltageRangeCheck({this.min, this.max, this.error});
  final int? min;
  final int? max;
  final VoltageRangeError? error;
}

const maxVoltageBound = 100000;

/// Checks the min/max text fields of a supply with nominal voltage [nominal]: both or neither,
/// whole numbers from 1 to 100000, min <= max and the nominal voltage within the bounds.
VoltageRangeCheck checkVoltageRange({
  required int nominal,
  required String min,
  required String max,
}) {
  final lo = min.trim();
  final hi = max.trim();
  if (lo.isEmpty && hi.isEmpty) return const VoltageRangeCheck();
  if (lo.isEmpty || hi.isEmpty) {
    return const VoltageRangeCheck(error: VoltageRangeError.incomplete);
  }
  final a = int.tryParse(lo);
  final b = int.tryParse(hi);
  if (a == null ||
      b == null ||
      a < 1 ||
      b < 1 ||
      a > maxVoltageBound ||
      b > maxVoltageBound) {
    return const VoltageRangeCheck(error: VoltageRangeError.invalid);
  }
  if (a > b) return const VoltageRangeCheck(error: VoltageRangeError.order);
  if (nominal < a || nominal > b) {
    return const VoltageRangeCheck(error: VoltageRangeError.nominalOutside);
  }
  return VoltageRangeCheck(min: a, max: b);
}
