import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/nav/nav_text.dart';

void main() {
  group('distanceMetres', () {
    test('reads what Google Maps wrote in a capture', () {
      expect(NavText.distanceMetres('650 m'), 650);
      expect(NavText.distanceMetres('0 m'), 0);
      expect(NavText.distanceMetres('6.7 km'), closeTo(6700, 1e-9));
    });

    test('reads miles, feet and yards', () {
      expect(NavText.distanceMetres('0.3 mi'), closeTo(482.8032, 1e-6));
      expect(NavText.distanceMetres('500 ft'), closeTo(152.4, 1e-9));
      expect(NavText.distanceMetres('200 yd'), closeTo(182.88, 1e-9));
    });

    test('takes a decimal comma and a grouped thousand', () {
      expect(NavText.distanceMetres('1,2 km'), closeTo(1200, 1e-9));
      expect(NavText.distanceMetres('1,234 m'), 1234);
      expect(NavText.distanceMetres('1.234.567 m'), 1234567);
      expect(NavText.distanceMetres('1.234,5 m'), closeTo(1234.5, 1e-9));
    });

    test('reads digits of another script', () {
      // Kannada 6, 5, 0 and Arabic-Indic 3, 0, 0.
      final kannada = String.fromCharCodes([0x0CEC, 0x0CEB, 0x0CE6]);
      final arabic = String.fromCharCodes([0x0663, 0x0660, 0x0660]);
      expect(NavText.distanceMetres('$kannada m'), 650);
      expect(NavText.distanceMetres('$arabic m'), 300);
    });

    test('does not guess a unit it has not seen', () {
      expect(NavText.distanceMetres('650 parsecs'), isNull);
      expect(
        NavText.distanceMetres('650 ${String.fromCharCode(0x0CAE)}'),
        isNull,
      );
    });

    test('takes the unit table it is given', () {
      expect(NavText.distanceMetres('650 foo', units: const {'foo': 2}), 1300);
    });

    test('wants a number and a unit and nothing else', () {
      expect(NavText.distanceMetres(''), isNull);
      expect(NavText.distanceMetres('m'), isNull);
      expect(NavText.distanceMetres('650'), isNull);
      expect(NavText.distanceMetres('650 m · Turn right'), isNull);
      expect(NavText.distanceMetres('Turn right'), isNull);
    });
  });

  group('duration', () {
    test('reads minutes, hours and days', () {
      expect(NavText.duration('28 min'), const Duration(minutes: 28));
      expect(
        NavText.duration('1 h 5 min'),
        const Duration(hours: 1, minutes: 5),
      );
      expect(
        NavText.duration('1 hr 5 min'),
        const Duration(hours: 1, minutes: 5),
      );
      expect(NavText.duration('2 hr'), const Duration(hours: 2));
      expect(
        NavText.duration('2 days 3 hr'),
        const Duration(days: 2, hours: 3),
      );
    });

    test('is not fooled by a distance or a time of day', () {
      expect(NavText.duration('6.7 km'), isNull);
      expect(NavText.duration('650 m'), isNull);
      expect(NavText.duration('9:25 PM ETA'), isNull);
    });
  });

  group('clock', () {
    test('reads a 12 hour time as Google Maps wrote it', () {
      final c = NavText.clock('Arrive 9:25 PM');
      expect(c, isNotNull);
      expect(c!.text, '9:25 PM');
      expect((c.hour, c.minute), (21, 25));
    });

    test('puts midnight and noon where they belong', () {
      expect(NavText.clock('12:05 AM')!.hour, 0);
      expect(NavText.clock('12:05 PM')!.hour, 12);
      expect(NavText.clock('1:00 AM')!.hour, 1);
      expect(NavText.clock('11:59 PM')!.hour, 23);
    });

    test('reads a 24 hour time and a dotted one', () {
      expect(
        (NavText.clock('Arrive 21:25')!.hour, NavText.clock('21:25')!.minute),
        (21, 25),
      );
      expect(NavText.clock('9.25 pm')!.hour, 21);
      expect(NavText.clock('9:25 p.m.')!.hour, 21);
    });

    test('reads it through a narrow no-break space', () {
      expect(NavText.clock('9:25 PM')!.hour, 21);
      expect(NavText.clock('9:25 PM')!.hour, 21);
    });

    test('refuses what is not a time', () {
      expect(NavText.clock('28 min'), isNull);
      expect(NavText.clock('6.7 km'), isNull);
      expect(NavText.clock('13:30 PM'), isNull);
      expect(NavText.clock('25:00'), isNull);
      expect(NavText.clock('9:75'), isNull);
      expect(NavText.clock('Arrive '), isNull);
    });
  });

  test('parts splits at a middle dot, a bullet and a bar', () {
    expect(
      NavText.parts('28 min · 6.7 km · 9:25 PM ETA'),
      [
        '28 min',
        '6.7 km'.replaceAll(' ', ' '),
        '9:25 PM ETA',
      ].map((s) => s).toList(),
    );
    expect(NavText.parts('a • b | c'), ['a', 'b', 'c']);
    expect(NavText.parts('  '), isEmpty);
  });

  test('hasDigit sees a digit of any script', () {
    expect(NavText.hasDigit('Arrive 9:25 PM'), isTrue);
    expect(NavText.hasDigit('Arrive '), isFalse);
    expect(NavText.hasDigit(String.fromCharCode(0x0CEC)), isTrue);
  });
}
