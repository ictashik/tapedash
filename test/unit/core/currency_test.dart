import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/currency.dart';
import 'package:tapedash/core/number_format.dart';

void main() {
  group('Currency', () {
    test('the rupee is the default, with Indian grouping', () {
      expect(Currency.inr.code, 'INR');
      expect(Currency.inr.symbol, '₹');
      expect(Currency.inr.grouping, DigitGrouping.indian);
    });

    test('other currencies group in threes', () {
      expect(Currency.usd.grouping, DigitGrouping.western);
      expect(Currency.gbp.grouping, DigitGrouping.western);
    });

    test('a custom currency can be made', () {
      const custom = Currency(code: 'XOF', symbol: 'CFA');

      expect(formatMoney(2500, currency: custom), 'CFA2,500');
    });

    test('compares by value', () {
      expect(
        const Currency(
          code: 'INR',
          symbol: '₹',
          grouping: DigitGrouping.indian,
        ),
        Currency.inr,
      );
      expect(Currency.usd, isNot(Currency.gbp));
      expect(Currency.inr.hashCode, Currency.inr.hashCode);
    });
  });

  group('formatMoney in rupees', () {
    final cases = <double, String>{
      0.0: '₹0',
      7.0: '₹7',
      24.0: '₹24',
      999.0: '₹999',
      1000.0: '₹1,000',
      12345.0: '₹12,345',
      99999.0: '₹99,999',
      100000.0: '₹1,00,000',
      123456.0: '₹1,23,456',
      1234567.0: '₹12,34,567',
      12345678.0: '₹1,23,45,678',
    };
    cases.forEach((amount, expected) {
      test('$amount is $expected', () {
        expect(formatMoney(amount), expected);
      });
    });

    test('the rupee sign is directly before the number, with no space', () {
      final text = formatMoney(24);

      expect(text.codeUnitAt(0), 0x20B9);
      expect(text.codeUnitAt(1), '2'.codeUnitAt(0));
    });

    test('rounds to whole rupees', () {
      expect(formatMoney(24.4), '₹24');
      expect(formatMoney(24.5), '₹25');
      expect(formatMoney(24.6), '₹25');
      expect(formatMoney(999.5), '₹1,000');
    });

    test('shows the decimals asked for', () {
      expect(formatMoney(6.84, decimals: 1), '₹6.8');
      expect(formatMoney(104.35, decimals: 2), '₹104.35');
      expect(formatMoney(1234.5, decimals: 1), '₹1,234.5');
      expect(formatMoney(100, decimals: 2), '₹100.00');
    });

    test('puts the sign before the symbol, using U+2212', () {
      expect(formatMoney(-24), '−₹24');
      expect(formatMoney(-123456), '−₹1,23,456');
      expect(formatMoney(-1234.5, decimals: 1), '−₹1,234.5');
    });

    test('an amount that rounds to nothing is ₹0, never −₹0', () {
      expect(formatMoney(-0.3), '₹0');
      expect(formatMoney(-0.0), '₹0');
      expect(formatMoney(-0.04, decimals: 1), '₹0.0');
    });

    test('a missing amount is the missing-value text, without a symbol', () {
      expect(formatMoney(null), noValue);
      expect(formatMoney(double.nan), noValue);
      expect(formatMoney(double.infinity), noValue);
      expect(formatMoney(null, decimals: 2), noValue);
    });
  });

  group('formatMoney in other currencies', () {
    test('US dollars', () {
      expect(formatMoney(1234567, currency: Currency.usd), r'$1,234,567');
      expect(
        formatMoney(-9.99, currency: Currency.usd, decimals: 2),
        '−\$9.99',
      );
    });

    test('pounds', () {
      expect(formatMoney(1234, currency: Currency.gbp), '£1,234');
    });
  });
}
