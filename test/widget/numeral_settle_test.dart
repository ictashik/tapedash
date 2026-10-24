// NumeralSettle (DESIGN.md 5.6, "static numbers in parked views are set
// normally"): the numerals below it glide to the value rounded to the digits they
// show as the share rises to 1, and back to the live one as it falls.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/numeral_settle.dart';
import 'package:tapedash/ui/design/components/rolling_numerals.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/numeral_source.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';

import '../design/support/harness.dart';

class _Value extends ChangeNotifier implements NumeralSource {
  _Value(this._v);
  double _v;

  @override
  double get value => _v;
  set value(double v) {
    _v = v;
    notifyListeners();
  }

  @override
  double get staleness => 0;

  @override
  bool get hasValue => true;
}

void main() {
  setUpAll(loadTapeFonts);

  group('SettledSource', () {
    test('is the live value at 0 and the rounded one at 1', () {
      final raw = _Value(7.62);
      final share = ValueNotifier(0.0);
      final s = SettledSource(source: raw, share: share, decimals: 0);
      expect(s.value, 7.62);
      share.value = 1;
      expect(s.value, 8);
      share.value = 0.5;
      expect(s.value, closeTo(7.81, 1e-9));
      s.dispose();
    });

    test('rounds to the digits shown: one decimal, and a negative', () {
      final raw = _Value(-3.46);
      final share = ValueNotifier(1.0);
      expect(SettledSource(source: raw, share: share, decimals: 1).value, -3.5);
      expect(SettledSource(source: raw, share: share, decimals: 0).value, -3);
    });

    test(
      'notifies when the value or the share moves, and lets go when done',
      () {
        final raw = _Value(1.4);
        final share = ValueNotifier(0.0);
        final s = SettledSource(source: raw, share: share, decimals: 0);
        var n = 0;
        s.addListener(() => n++);
        raw.value = 2.2;
        share.value = 1;
        expect(n, 2);
        s.dispose();
        raw.value = 3;
        expect(n, 2);
      },
    );

    test('says what its source says about staleness and having a value', () {
      final raw = _Value(1);
      final s = SettledSource(
        source: raw,
        share: ValueNotifier(1.0),
        decimals: 0,
      );
      expect(s.hasValue, isTrue);
      expect(s.staleness, 0);
    });
  });

  testWidgets('rolling numerals under it rest on a whole digit when parked', (
    tester,
  ) async {
    setWindow(tester, const Size(200, 200));
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    final raw = _Value(7.62);
    final share = ValueNotifier(0.0);

    Widget readout({required bool settled}) {
      final numerals = RollingNumerals(
        source: raw,
        format: const NumeralFormat(integerDigits: 2),
        size: 60,
      );
      return Center(
        child: settled
            ? NumeralSettle(share: share, child: numerals)
            : numerals,
      );
    }

    Future<List<int>> picture(bool settled) async {
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          child: readout(settled: settled),
        ),
      );
      final png = await capturePng(tester, 'settle-probe');
      return png;
    }

    // Live, 7.62 is part-way through its roll: not the same picture as 8.
    final live = await picture(false);
    raw.value = 8;
    final eight = await picture(false);
    expect(live, isNot(eight));

    // Settled and parked, 7.62 draws as the 8 it rests on.
    raw.value = 7.62;
    share.value = 1;
    final parked = await picture(true);
    expect(parked, eight);

    // And not parked it is live again.
    share.value = 0;
    final moving = await picture(true);
    expect(moving, live);

    motion.dispose();
    kit.dispose();
  });
}
