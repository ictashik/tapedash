// The Pit Stop form's typing and validation (DESIGN.md 7.9, CLAUDE.md 8.5).
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/money/pit_stop_form.dart';

void type(PitStopForm f, String keys) {
  for (final k in keys.split(',')) {
    f.press(k);
  }
}

void main() {
  group('typing', () {
    test('digits, a decimal point and back', () {
      final f = PitStopForm();
      type(f, '2,5,.,7');
      expect(f.litresText, '25.7');
      f.press('back');
      expect(f.litresText, '25.');
      f.press('back');
      f.press('back');
      expect(f.litresText, '2');
      f.press('back');
      f.press('back'); // safe when empty.
      expect(f.litresText, '');
    });

    test('a decimal point first is 0.', () {
      final f = PitStopForm()..press('.');
      expect(f.litresText, '0.');
    });

    test('a second decimal point is ignored', () {
      final f = PitStopForm();
      type(f, '1,.,5,.,2');
      expect(f.litresText, '1.52');
    });

    test('at most two decimals', () {
      final f = PitStopForm();
      type(f, '1,.,2,3,4');
      expect(f.litresText, '1.23');
    });

    test('no leading zeros', () {
      final f = PitStopForm();
      type(f, '0,5');
      expect(f.litresText, '5');
      final g = PitStopForm();
      type(g, '0,0,0');
      expect(g.litresText, '0');
    });

    test('litres stop at three integer digits, the amount at six', () {
      final f = PitStopForm();
      type(f, '1,2,3,4');
      expect(f.litresText, '123');
      f.active = PitStopField.amount;
      type(f, '1,2,3,4,5,6,7');
      expect(f.amountText, '123456');
    });

    test('anything else is ignored', () {
      final f = PitStopForm();
      type(f, 'x,-,12,a');
      expect(f.litresText, '');
    });

    test('keys go to the active field', () {
      final f = PitStopForm();
      type(f, '3,0');
      f.active = PitStopField.amount;
      type(f, '3,0,0,0');
      expect(f.litresText, '30');
      expect(f.amountText, '3000');
    });
  });

  group('the price', () {
    test('is the amount over the litres', () {
      final f = PitStopForm();
      type(f, '2,0');
      f.active = PitStopField.amount;
      type(f, '2,0,5,0');
      expect(f.pricePerLitre, closeTo(102.5, 1e-9));
    });

    test('is null until both are typed, and with 0 litres', () {
      final f = PitStopForm();
      expect(f.pricePerLitre, isNull);
      type(f, '2,0');
      expect(f.pricePerLitre, isNull);
      final g = PitStopForm();
      type(g, '0');
      g.active = PitStopField.amount;
      type(g, '5,0,0');
      expect(g.pricePerLitre, isNull);
    });
  });

  group('validation', () {
    PitStopForm filled(String litres, String amount, {double tank = 40}) {
      final f = PitStopForm(tankLitres: tank);
      for (final c in litres.split('')) {
        f.press(c);
      }
      f.active = PitStopField.amount;
      for (final c in amount.split('')) {
        f.press(c);
      }
      return f;
    }

    test('a sensible fill-up saves', () {
      final f = filled('32.5', '3331.25');
      expect(f.issues(), isEmpty);
      expect(f.canSave, isTrue);
    });

    test('empty fields are missing', () {
      final f = PitStopForm();
      expect(f.issues(), [
        PitStopIssue.litresMissing,
        PitStopIssue.amountMissing,
      ]);
      expect(f.canSave, isFalse);
    });

    test('zero litres or zero amount is missing', () {
      expect(filled('0', '100').issues(), contains(PitStopIssue.litresMissing));
      expect(filled('10', '0').issues(), contains(PitStopIssue.amountMissing));
    });

    test('more than the tank by a margin is too many', () {
      expect(filled('50', '5000').issues(), isEmpty, reason: '1.25 x 40 = 50');
      expect(
        filled('51', '5100').issues(),
        contains(PitStopIssue.litresTooMany),
      );
    });

    test('a price no fuel costs is implausible, either way', () {
      expect(
        filled('10', '0.5').issues(),
        contains(PitStopIssue.priceImplausible),
      );
      expect(
        filled('1', '100000').issues(),
        contains(PitStopIssue.priceImplausible),
      );
    });

    test('the price-only form needs just a plausible price', () {
      final f = PitStopForm(priceOnly: true);
      expect(f.active, PitStopField.amount);
      expect(f.issues(), [PitStopIssue.amountMissing]);
      type(f, '1,0,2,.,5');
      expect(f.issues(), isEmpty);
      expect(f.pricePerLitre, 102.5);
      final g = PitStopForm(priceOnly: true);
      type(g, '5,0,0,0');
      expect(g.issues(), contains(PitStopIssue.priceImplausible));
    });

    test('full tank starts on', () {
      expect(PitStopForm().fullTank, isTrue);
    });
  });
}
