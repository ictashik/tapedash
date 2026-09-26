import 'number_format.dart';

/// A currency for showing money. It defaults to the rupee (CLAUDE.md 8.5).
///
/// Fuel prices are always entered by the user and never fetched, so this only
/// describes how an amount is written.
class Currency {
  const Currency({
    required this.code,
    required this.symbol,
    this.grouping = DigitGrouping.western,
  });

  /// ISO 4217 code, such as `INR`.
  final String code;

  /// Written directly before the number, with no space.
  final String symbol;

  final DigitGrouping grouping;

  static const Currency inr = Currency(
    code: 'INR',
    symbol: '₹',
    grouping: DigitGrouping.indian,
  );

  static const Currency usd = Currency(code: 'USD', symbol: r'$');

  static const Currency gbp = Currency(code: 'GBP', symbol: '£');

  @override
  bool operator ==(Object other) =>
      other is Currency &&
      other.code == code &&
      other.symbol == symbol &&
      other.grouping == grouping;

  @override
  int get hashCode => Object.hash(code, symbol, grouping);

  @override
  String toString() => 'Currency($code)';
}

/// Formats an amount of money, such as `₹1,23,456`.
///
/// The symbol comes directly before the number, and the sign before the
/// symbol: `−₹24`. Amounts are estimates, so show whole units unless a decimal
/// is meant: whole rupees for a trip's cost, one decimal for ₹/km, two for a
/// price per litre (DESIGN.md 10). An amount that rounds to nothing is `₹0`,
/// never `−₹0`. A missing or non-finite amount is [noValue].
String formatMoney(
  double? amount, {
  Currency currency = Currency.inr,
  int decimals = 0,
}) {
  final number = formatNumber(
    amount,
    decimals: decimals,
    grouping: currency.grouping,
  );
  if (number == noValue) return noValue;

  return number.startsWith(minusSign)
      ? '$minusSign${currency.symbol}${number.substring(minusSign.length)}'
      : '${currency.symbol}$number';
}
