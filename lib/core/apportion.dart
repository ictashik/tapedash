/// Rounds [values] to whole numbers that add up to their own total, rounded
/// (CLAUDE.md 1.6: never show false precision, and CLAUDE.md 8.7: the buckets sum
/// to the trip).
///
/// Each part is first rounded down; the parts with the largest remainders then
/// get the one extra each that the total is short of (the largest-remainder
/// method). So 24.6 and 3.7, which are 25 and 4 rounded one by one and add up to
/// 29 against a total of 28.3, come out as 24 and 4. A part is never moved by
/// more than one from its own rounding. Negative and non-finite parts count as 0.
///
/// [total] is what the parts must add up to, if not the rounded sum of the parts.
List<int> apportion(List<double> values, {int? total}) {
  final clean = [for (final v in values) v.isFinite && v > 0 ? v : 0.0];
  final target = total ?? clean.fold<double>(0, (a, b) => a + b).round();
  final floors = [for (final v in clean) v.floor()];
  var short = target - floors.fold<int>(0, (a, b) => a + b);
  if (short <= 0) {
    // More than the total already (only if [total] was given low): take back
    // from the smallest remainders.
    final order = List<int>.generate(clean.length, (i) => i)
      ..sort((a, b) {
        final byRemainder = (clean[a] - floors[a]).compareTo(
          clean[b] - floors[b],
        );
        return byRemainder != 0 ? byRemainder : a.compareTo(b);
      });
    for (final i in order) {
      if (short == 0) break;
      if (floors[i] > 0) {
        floors[i]--;
        short++;
      }
    }
    return floors;
  }
  final order = List<int>.generate(clean.length, (i) => i)
    ..sort((a, b) {
      final byRemainder = (clean[b] - floors[b]).compareTo(
        clean[a] - floors[a],
      );
      return byRemainder != 0 ? byRemainder : a.compareTo(b);
    });
  for (var k = 0; short > 0; k = (k + 1) % order.length) {
    floors[order[k]]++;
    short--;
  }
  return floors;
}
