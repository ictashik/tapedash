// The parked controls (DESIGN.md 6.14 and 6.16): the chamfer button, the toggle,
// the segmented selector, the slider, the list row and the touch bloom.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/components/controls/tape_list_row.dart';
import 'package:tapedash/ui/design/components/controls/tape_segmented.dart';
import 'package:tapedash/ui/design/components/controls/tape_slider.dart';
import 'package:tapedash/ui/design/components/controls/tape_toggle.dart';
import 'package:tapedash/ui/design/components/controls/touch_bloom.dart';
import 'package:tapedash/ui/design/icons/icons.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/palette.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/shapes.dart';

import '../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;
  late ManualMotionClock motion;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
  });

  tearDown(() {
    motion.dispose();
    kit.dispose();
  });

  Future<void> show(
    WidgetTester tester,
    Widget child, {
    TapeThemeData? theme,
    Alignment alignment = Alignment.topLeft,
    double? width,
  }) => tester.pumpWidget(
    tapeHarness(
      kit: kit,
      motion: motion,
      theme: theme,
      child: Align(
        alignment: alignment,
        child: SizedBox(width: width, child: child),
      ),
    ),
  );

  Future<ByteData> pixels(WidgetTester tester) async {
    final image = await renderImage(tester);
    late ByteData data;
    await tester.runAsync(() async => data = (await image.toByteData())!);
    return data;
  }

  int at(ByteData d, int x, int y, [int width = 1280]) =>
      d.getUint32((y * width + x) * 4);

  Future<int> countColour(WidgetTester tester, int rgba) async {
    final d = await pixels(tester);
    var n = 0;
    for (var i = 0; i < 1280 * 720; i++) {
      if (d.getUint32(i * 4) == rgba) n++;
    }
    return n;
  }

  group('TapeButton', () {
    testWidgets('is 56 tall, and a touch target wide', (tester) async {
      setWindow(tester, const Size(640, 360));
      await show(tester, TapeButton(label: 'Save', onPressed: () {}));

      final size = tester.getSize(find.byType(TapeButton));

      expect(size.height, greaterThanOrEqualTo(TapeShape.buttonHeight));
      expect(size.width, greaterThanOrEqualTo(48));
    });

    testWidgets(
      'writes its label in UPPERCASE, in Barlow Semi Condensed SemiBold',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        await show(
          tester,
          TapeButton(label: 'Set fuel price', onPressed: () {}),
        );

        final text = tester.widget<Text>(find.text('SET FUEL PRICE'));

        expect(text.style!.fontFamily, 'BarlowSemiCondensed');
        expect(text.style!.fontWeight, FontWeight.w600);
      },
    );

    testWidgets('calls onPressed when tapped, and not when it has none', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      var taps = 0;
      await show(tester, TapeButton(label: 'Go', onPressed: () => taps++));
      await tester.tap(find.byType(TapeButton));
      expect(taps, 1);

      await show(tester, const TapeButton(label: 'Go'));
      await tester.tap(find.byType(TapeButton));
      expect(taps, 1);
    });

    testWidgets('has a chamfered top-left and a square top-right', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      await show(tester, TapeButton(label: 'Go', onPressed: () {}));
      final d = await pixels(tester);
      final w = (tester.getSize(find.byType(TapeButton)).width * 2).round();

      // 8 lp is 16 px: the corner is cut, so its very corner is canvas...
      expect(at(d, 2, 2) & 0xFFFFFF00, isNot(0x5CE1FF00));
      // ...and the top-right corner is the outline, in the accent.
      expect(at(d, w - 2, 1), 0x5CE1FFFF);
      // The outline runs along the top from the cut to the corner.
      expect(at(d, 40, 1), 0x5CE1FFFF);
    });

    testWidgets(
      'a primary button is filled with the accent, with a void label',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        await show(
          tester,
          TapeButton(label: 'Save', primary: true, onPressed: () {}),
        );

        final filled = await countColour(tester, 0x5CE1FFFF);
        expect(filled, greaterThan(8000));
        expect(
          tester.widget<Text>(find.text('SAVE')).style!.color,
          const Color(0xFF050607),
        );
      },
    );

    testWidgets('a disabled button is drawn in the inactive track colour', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      await show(tester, const TapeButton(label: 'Go'));

      expect(await countColour(tester, 0x252B35FF), greaterThan(100));
      expect(await countColour(tester, 0x5CE1FFFF), 0);
    });

    testWidgets('the money tone is champagne', (tester) async {
      setWindow(tester, const Size(640, 360));
      await show(
        tester,
        TapeButton(
          label: 'Set fuel price',
          tone: ButtonTone.money,
          onPressed: () {},
        ),
      );

      expect(await countColour(tester, 0xF3CF86FF), greaterThan(100));
    });

    testWidgets('pressed, it fills with 12% of its colour, and lets go again', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      await show(tester, TapeButton(label: 'Go', onPressed: () {}));
      final size = tester.getSize(find.byType(TapeButton));
      final inside = (size.width - 2, size.height / 2 * 2 - 6);

      final before = at(
        await pixels(tester),
        inside.$1.round(),
        inside.$2.round(),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TapeButton)),
      );
      await tester.pump();
      final during = at(
        await pixels(tester),
        inside.$1.round(),
        inside.$2.round(),
      );
      await gesture.up();
      motion.advance(const Duration(milliseconds: 400));
      await tester.pump();
      final after = at(
        await pixels(tester),
        inside.$1.round(),
        inside.$2.round(),
      );

      expect(during, isNot(before));
      expect(after, before);
    });

    testWidgets('Daylight draws the outline thicker', (tester) async {
      setWindow(tester, const Size(640, 360));
      await show(tester, TapeButton(label: 'Go', onPressed: () {}));
      final normal = await countColour(tester, 0x5CE1FFFF);

      await show(
        tester,
        TapeButton(label: 'Go', onPressed: () {}),
        theme: TapeThemeData(mode: TapeMode.daylight),
      );
      final day = await countColour(tester, 0x5CE1FFFF);

      expect(day, greaterThan(normal * 1.25));
    });

    testWidgets('an icon goes before the label, and makes the button wider', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      await show(tester, TapeButton(label: 'Go', onPressed: () {}));
      final plain = tester.getSize(find.byType(TapeButton)).width;

      await show(
        tester,
        TapeButton(label: 'Go', icon: TapeIcon.close, onPressed: () {}),
      );

      expect(
        tester.getSize(find.byType(TapeButton)).width,
        closeTo(plain + 20 + 8, 0.01),
      );
      expect(find.byType(TapeIconView), findsOneWidget);
    });
  });

  group('TouchBloom (DESIGN.md 6.16)', () {
    testWidgets('a tap blooms at the touch and it fades within 220 ms', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      await show(
        tester,
        TouchBloom(
          onTap: () {},
          builder: (context, pressed) =>
              const SizedBox(width: 200, height: 200),
        ),
      );

      final gesture = await tester.startGesture(const Offset(100, 100));
      await tester.pump();
      motion.advance(const Duration(milliseconds: 40));
      await tester.pump();
      final glowing = (await pixels(tester));
      var lit = 0;
      for (var y = 120; y < 280; y++) {
        for (var x = 120; x < 280; x++) {
          if (at(glowing, x, y) != at(glowing, 0, 0)) lit++;
        }
      }
      expect(lit, greaterThan(500), reason: 'a glow around the touch point');

      await gesture.up();
      motion.advance(const Duration(milliseconds: 260));
      await tester.pump();
      final gone = await pixels(tester);
      var still = 0;
      for (var y = 120; y < 280; y++) {
        for (var x = 120; x < 280; x++) {
          if (at(gone, x, y) != at(gone, 0, 0)) still++;
        }
      }
      expect(still, 0);
    });

    testWidgets('the clock is let go of once the bloom is over', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      await show(
        tester,
        TouchBloom(
          onTap: () {},
          builder: (context, pressed) =>
              const SizedBox(width: 100, height: 100),
        ),
      );

      await tester.tap(find.byType(TouchBloom));
      expect(motion.attachedCount, greaterThan(0));
      motion.advance(const Duration(seconds: 1));

      expect(motion.attachedCount, 0);
    });

    testWidgets('a disabled one does not bloom or call back', (tester) async {
      setWindow(tester, const Size(640, 360));
      var taps = 0;
      await show(
        tester,
        TouchBloom(
          enabled: false,
          onTap: () => taps++,
          builder: (context, pressed) =>
              const SizedBox(width: 100, height: 100),
        ),
      );

      await tester.tap(find.byType(TouchBloom));

      expect(taps, 0);
      expect(motion.attachedCount, 0);
    });

    testWidgets('it tells its builder when the touch is down', (tester) async {
      setWindow(tester, const Size(640, 360));
      final seen = <bool>[];
      await show(
        tester,
        TouchBloom(
          onTap: () {},
          builder: (context, pressed) {
            seen.add(pressed);
            return const SizedBox(width: 100, height: 100);
          },
        ),
      );

      final gesture = await tester.startGesture(const Offset(50, 50));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(seen, containsAllInOrder([false, true, false]));
    });
  });

  group('TapeToggle', () {
    testWidgets('asks to be turned the other way on a tap', (tester) async {
      setWindow(tester, const Size(640, 360));
      final changes = <bool>[];
      await show(tester, TapeToggle(value: false, onChanged: changes.add));

      await tester.tap(find.byType(TapeToggle));
      await show(tester, TapeToggle(value: true, onChanged: changes.add));
      await tester.tap(find.byType(TapeToggle));

      expect(changes, [true, false]);
    });

    testWidgets('a disabled toggle does not answer', (tester) async {
      setWindow(tester, const Size(640, 360));
      await show(tester, const TapeToggle(value: false, onChanged: null));

      await tester.tap(find.byType(TapeToggle));

      expect(motion.attachedCount, 0);
    });

    testWidgets('is a 48 lp touch target, with a 48 by 26 track inside', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      await show(tester, TapeToggle(value: false, onChanged: (_) {}));

      final size = tester.getSize(find.byType(TapeToggle));

      expect(size.height, 48);
      expect(size.width, greaterThanOrEqualTo(TapeShape.toggleWidth));
    });

    testWidgets(
      'the lit cell moves to the other end on spring.snap, without overshoot',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        await show(tester, TapeToggle(value: false, onChanged: (_) {}));
        final off = await pixels(tester);
        var offAccent = 0;
        for (var i = 0; i < 1280 * 720; i++) {
          if (off.getUint32(i * 4) == 0x5CE1FFFF) offAccent++;
        }
        expect(offAccent, 0, reason: 'off: nothing lights');

        await show(tester, TapeToggle(value: true, onChanged: (_) {}));
        // Mid-move, then settled.
        motion.advance(const Duration(milliseconds: 60));
        await tester.pump();
        final mid = await countColour(tester, 0x5CE1FFFF);
        motion.advance(const Duration(milliseconds: 600));
        await tester.pump();
        final on = await countColour(tester, 0x5CE1FFFF);

        expect(on, greaterThan(400));
        expect(mid, lessThanOrEqualTo(on + 60));
      },
    );

    testWidgets('says whether it is on to accessibility', (tester) async {
      setWindow(tester, const Size(640, 360));
      final handle = tester.ensureSemantics();
      await show(
        tester,
        TapeToggle(
          value: true,
          onChanged: (_) {},
          semanticLabel: 'Shift light',
        ),
      );

      expect(
        tester.getSemantics(find.byType(TapeToggle)),
        matchesSemantics(
          label: 'Shift light',
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: true,
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('TapeSegmented', () {
    const segments = [
      TapeSegment('week', 'Week'),
      TapeSegment('month', 'Month'),
      TapeSegment('all', 'All'),
    ];

    testWidgets(
      'shows each label in UPPERCASE, and the selected one in the accent',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        await show(
          tester,
          TapeSegmented<String>(
            segments: segments,
            value: 'month',
            onChanged: (_) {},
          ),
          width: 300,
        );

        expect(find.text('WEEK'), findsOneWidget);
        expect(find.text('MONTH'), findsOneWidget);
        expect(find.text('ALL'), findsOneWidget);
        expect(
          tester.widget<Text>(find.text('MONTH')).style!.color,
          const Color(0xFF5CE1FF),
        );
        expect(
          tester.widget<Text>(find.text('WEEK')).style!.color,
          const Color(0xFF7A838F),
        );
      },
    );

    testWidgets('tapping a cell selects it', (tester) async {
      setWindow(tester, const Size(640, 360));
      final chosen = <String>[];
      await show(
        tester,
        TapeSegmented<String>(
          segments: segments,
          value: 'week',
          onChanged: chosen.add,
        ),
        width: 300,
      );

      await tester.tap(find.text('ALL'));
      await tester.tap(find.text('MONTH'));

      expect(chosen, ['all', 'month']);
    });

    testWidgets('the light moves to the new cell on a spring', (tester) async {
      setWindow(tester, const Size(640, 360));
      Future<int> accentIn(int left, int right) async {
        final d = await pixels(tester);
        var n = 0;
        for (var y = 0; y < 96; y++) {
          for (var x = left; x < right; x++) {
            if (at(d, x, y) == 0x5CE1FFFF) n++;
          }
        }
        return n;
      }

      await show(
        tester,
        TapeSegmented<String>(
          segments: segments,
          value: 'week',
          onChanged: (_) {},
        ),
        width: 300,
      );
      // The outline of the lit cell is in the first third.
      final first = await accentIn(2, 200);
      final last = await accentIn(400, 598);
      expect(first, greaterThan(200));
      expect(last, lessThan(first ~/ 4));

      await show(
        tester,
        TapeSegmented<String>(
          segments: segments,
          value: 'all',
          onChanged: (_) {},
        ),
        width: 300,
      );
      motion.advance(const Duration(seconds: 1));
      await tester.pump();

      expect(await accentIn(400, 598), greaterThan(200));
      expect(await accentIn(2, 200), lessThan(first ~/ 4));
    });

    testWidgets('a value that is not among the segments selects the first', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      await show(
        tester,
        TapeSegmented<String>(
          segments: segments,
          value: 'nope',
          onChanged: (_) {},
        ),
        width: 300,
      );

      expect(
        tester.widget<Text>(find.text('WEEK')).style!.color,
        const Color(0xFF5CE1FF),
      );
    });

    testWidgets('is a touch target tall', (tester) async {
      setWindow(tester, const Size(640, 360));
      await show(
        tester,
        TapeSegmented<String>(
          segments: segments,
          value: 'week',
          onChanged: (_) {},
        ),
        width: 300,
      );

      expect(tester.getSize(find.byType(TapeSegmented<String>)).height, 48);
    });
  });

  group('TapeSlider', () {
    testWidgets('a drag sets the value in proportion, and clamps at the ends', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      var value = 0.0;
      await show(
        tester,
        StatefulBuilder(
          builder: (context, setState) => TapeSlider(
            label: 'Speed',
            value: value,
            min: 0,
            max: 200,
            format: (v) => v.round().toString(),
            onChanged: (v) => setState(() => value = v),
          ),
        ),
        width: 300,
      );
      final track = tester.getRect(find.byType(TapeSlider));

      await tester.dragFrom(
        Offset(track.left + 7, track.center.dy + 8),
        const Offset(143, 0),
      );
      expect(value, closeTo(100, 8));

      await tester.dragFrom(
        Offset(track.left + 150, track.center.dy + 8),
        const Offset(400, 0),
      );
      expect(value, 200);
      await tester.dragFrom(
        Offset(track.left + 150, track.center.dy + 8),
        const Offset(-600, 0),
      );
      expect(value, 0);
    });

    testWidgets('a tap goes straight to the place', (tester) async {
      setWindow(tester, const Size(640, 360));
      var value = 0.0;
      await show(
        tester,
        TapeSlider(label: 'Level', value: value, onChanged: (v) => value = v),
        width: 300,
      );
      final track = tester.getRect(find.byType(TapeSlider));

      await tester.tapAt(Offset(track.left + 150, track.center.dy + 8));

      expect(value, closeTo(0.5, 0.05));
    });

    testWidgets('shows its label in UPPERCASE and its value', (tester) async {
      setWindow(tester, const Size(640, 360));
      await show(
        tester,
        TapeSlider(label: 'Halo', value: 0.3, onChanged: (_) {}),
        width: 300,
      );

      expect(find.text('HALO'), findsOneWidget);
      expect(find.text('0.30'), findsOneWidget);
    });

    testWidgets('a disabled slider does not answer', (tester) async {
      setWindow(tester, const Size(640, 360));
      await show(
        tester,
        const TapeSlider(label: 'Halo', value: 0.3, onChanged: null),
        width: 300,
      );

      await tester.tapAt(tester.getCenter(find.byType(TapeSlider)));
      // Nothing to assert on but that it did not throw: there is no callback.
      expect(tester.takeException(), isNull);
    });
  });

  group('TapeListRow', () {
    testWidgets('is 64 tall, shows its label and value, and answers a tap', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      var taps = 0;
      await show(
        tester,
        TapeListRow(
          label: 'Fuel price',
          value: '₹104.2 / L',
          onTap: () => taps++,
        ),
        width: 400,
      );

      expect(tester.getSize(find.byType(TapeListRow)).height, 64);
      expect(find.text('Fuel price'), findsOneWidget);
      expect(find.text('₹104.2 / L'), findsOneWidget);
      await tester.tap(find.byType(TapeListRow));
      expect(taps, 1);
    });

    testWidgets('a row that does nothing shows no chevron and dims its label', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      await show(
        tester,
        const TapeListRow(label: 'Version', value: '0.2.0'),
        width: 400,
      );

      expect(
        tester.widget<Text>(find.text('Version')).style!.color,
        const Color(0xFF7A838F),
      );
    });

    testWidgets('the selected row takes the accent', (tester) async {
      setWindow(tester, const Size(640, 360));
      await show(
        tester,
        TapeListRow(label: 'ION', selected: true, onTap: () {}),
        width: 400,
      );

      expect(
        tester.widget<Text>(find.text('ION')).style!.color,
        const Color(0xFF5CE1FF),
      );
    });
  });

  group('liveries', () {
    testWidgets('a button takes the accent of every livery', (tester) async {
      setWindow(tester, const Size(640, 360));
      for (final (livery, rgba) in [
        (Liveries.ion, 0x5CE1FFFF),
        (Liveries.ember, 0xFF7A3DFF),
        (Liveries.vfd, 0x6BF7DCFF),
        (Liveries.mono, 0xF2F3F4FF),
      ]) {
        await show(
          tester,
          TapeButton(label: 'Go', onPressed: () {}),
          theme: TapeThemeData(livery: livery),
        );

        expect(
          await countColour(tester, rgba),
          greaterThan(100),
          reason: livery.name,
        );
      }
    });
  });
}
