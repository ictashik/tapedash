/// What is shown where a value is missing or is not a number: an em dash,
/// never "NaN", "null" or "Infinity" (DESIGN.md 10, 15).
const String noValue = '—';

/// The minus sign: U+2212, not a hyphen (DESIGN.md 4.5).
const String minusSign = '−';

/// How the digits of a whole number are grouped.
enum DigitGrouping {
  /// 1234567
  none,

  /// 1,234,567
  western,

  /// 12,34,567: the last three digits, then pairs. Used for money (CLAUDE.md
  /// 8.5, DESIGN.md 10).
  indian,
}

/// Groups a string of plain digits, with commas.
String groupDigits(String digits, DigitGrouping grouping) {
  if (grouping == DigitGrouping.none || digits.length <= 3) return digits;

  final groupSize = grouping == DigitGrouping.indian ? 2 : 3;
  final tail = digits.substring(digits.length - 3);
  final head = digits.substring(0, digits.length - 3);

  // The head is grouped from the right, so its first group is the short one.
  final groups = <String>[];
  for (var end = head.length; end > 0; end -= groupSize) {
    final start = end - groupSize < 0 ? 0 : end - groupSize;
    groups.add(head.substring(start, end));
  }
  return '${groups.reversed.join(',')},$tail';
}

// toStringAsFixed switches to exponent notation from 1e21. Nothing TapeDash
// shows is anywhere near this, so treat it as garbage rather than print it.
const double _largestShown = 1e15;

/// Formats [value] with exactly [decimals] decimals.
///
/// Rounds half away from zero, uses [minusSign], and never shows a negative
/// zero: a value that rounds to nothing is "0", not "−0". A missing, infinite or
/// absurdly large value is [noValue].
String formatNumber(
  double? value, {
  int decimals = 0,
  DigitGrouping grouping = DigitGrouping.none,
}) {
  if (value == null || !value.isFinite || value.abs() >= _largestShown) {
    return noValue;
  }

  // Round first and look at the sign afterwards.
  final rounded = double.parse(value.toStringAsFixed(decimals));
  final fixed = rounded.abs().toStringAsFixed(decimals);
  final dot = fixed.indexOf('.');
  final integer = dot < 0 ? fixed : fixed.substring(0, dot);
  final fraction = dot < 0 ? '' : fixed.substring(dot);

  final sign = rounded < 0 ? minusSign : '';
  return '$sign${groupDigits(integer, grouping)}$fraction';
}
