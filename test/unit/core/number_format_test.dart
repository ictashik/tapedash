import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/number_format.dart';

void main() {
  test('the missing-value text is an em dash and the minus is U+2212', () {
    expect(noValue.codeUnits, [0x2014]);
    expect(minusSign.codeUnits, [0x2212]);
  });

  group('groupDigits', () {
    const indian = {
      '0': '0',
      '7': '7',
      '99': '99',
      '999': '999',
      '1000': '1,000',
      '12345': '12,345',
      '99999': '99,999',
      '100000': '1,00,000',
      '123456': '1,23,456',
      '1234567': '12,34,567',
      '12345678': '1,23,45,678',
      '123456789': '12,34,56,789',
      '1234567890': '1,23,45,67,890',
    };
    indian.forEach((digits, expected) {
      test('Indian: $digits is $expected', () {
        expect(groupDigits(digits, DigitGrouping.indian), expected);
      });
    });

    const western = {
      '999': '999',
      '1000': '1,000',
      '12345': '12,345',
      '123456': '123,456',
      '1234567': '1,234,567',
      '12345678': '12,345,678',
    };
    western.forEach((digits, expected) {
      test('western: $digits is $expected', () {
        expect(groupDigits(digits, DigitGrouping.western), expected);
      });
    });

    test('none leaves the digits alone', () {
      expect(groupDigits('1234567', DigitGrouping.none), '1234567');
    });

    test('an empty string stays empty', () {
      expect(groupDigits('', DigitGrouping.indian), '');
    });
  });

  group('formatNumber', () {
    test('whole numbers by default', () {
      expect(formatNumber(87), '87');
      expect(formatNumber(87.4), '87');
      expect(formatNumber(87.6), '88');
      expect(formatNumber(0), '0');
    });

    test('exactly the requested number of decimals, padded', () {
      expect(formatNumber(14.6237, decimals: 1), '14.6');
      expect(formatNumber(14, decimals: 1), '14.0');
      expect(formatNumber(14.6, decimals: 3), '14.600');
      expect(formatNumber(104.349, decimals: 2), '104.35');
    });

    test('rounds half away from zero', () {
      expect(formatNumber(0.5), '1');
      expect(formatNumber(1.5), '2');
      expect(formatNumber(2.5), '3');
      expect(formatNumber(-0.5), '−1');
      expect(formatNumber(-2.5), '−3');
      expect(formatNumber(0.125, decimals: 2), '0.13');
      expect(formatNumber(-0.125, decimals: 2), '−0.13');
    });

    test('a carry can change the number of digits', () {
      expect(formatNumber(9.96, decimals: 1), '10.0');
      expect(formatNumber(99.5), '100');
      expect(formatNumber(999.5), '1000');
    });

    test('uses U+2212 for the minus sign, never a hyphen', () {
      final text = formatNumber(-42);

      expect(text, '−42');
      expect(text.contains('-'), isFalse);
    });

    test('never shows a negative zero', () {
      expect(formatNumber(-0.0), '0');
      expect(formatNumber(-0.4), '0');
      expect(formatNumber(-0.04, decimals: 1), '0.0');
      expect(formatNumber(-0.0049, decimals: 2), '0.00');
    });

    test('a value that only just rounds away from zero keeps its sign', () {
      expect(formatNumber(-0.5), '−1');
      expect(formatNumber(-0.05, decimals: 1), '−0.1');
    });

    test('groups the integer part only', () {
      expect(
        formatNumber(1234567.891, decimals: 2, grouping: DigitGrouping.indian),
        '12,34,567.89',
      );
      expect(
        formatNumber(1234567.891, decimals: 2, grouping: DigitGrouping.western),
        '1,234,567.89',
      );
      expect(formatNumber(1234567.891, decimals: 2), '1234567.89');
    });

    test('groups a negative number', () {
      expect(
        formatNumber(-123456, grouping: DigitGrouping.indian),
        '−1,23,456',
      );
    });

    test('a carry into a new group is grouped correctly', () {
      expect(formatNumber(99999.6, grouping: DigitGrouping.indian), '1,00,000');
    });

    test(
      'missing, not-a-number and infinite values are the missing-value text',
      () {
        expect(formatNumber(null), noValue);
        expect(formatNumber(double.nan), noValue);
        expect(formatNumber(double.infinity), noValue);
        expect(formatNumber(double.negativeInfinity), noValue);
      },
    );

    test(
      'an absurdly large value is the missing-value text, not exponent notation',
      () {
        expect(formatNumber(1e21), noValue);
        expect(formatNumber(-1e15), noValue);
        expect(formatNumber(1e14), '100000000000000');
      },
    );

    test('the missing-value text never picks up a sign or grouping', () {
      expect(
        formatNumber(null, decimals: 2, grouping: DigitGrouping.indian),
        noValue,
      );
    });
  });
}
