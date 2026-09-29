// The status strip (DESIGN.md 6.9): the adapter glyph's states and its 0.5 Hz
// search pulse, the clock's 12/24-hour formatting, glyphs-only-in-Motion vs
// captions-in-Parked, and that live state repaints without a rebuild.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/status_strip.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';

import '../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  group('formatClock (DESIGN.md 6.9)', () {
    test('24-hour: zero-padded, no suffix', () {
      expect(formatClock(DateTime(2026, 1, 1, 9, 5), use24Hour: true), '09:05');
      expect(
        formatClock(DateTime(2026, 1, 1, 23, 59), use24Hour: true),
        '23:59',
      );
      expect(formatClock(DateTime(2026, 1, 1, 0, 0), use24Hour: true), '00:00');
    });

    test('12-hour: midnight and noon are both 12, with AM/PM', () {
      expect(
        formatClock(DateTime(2026, 1, 1, 0, 0), use24Hour: false),
        '12:00 AM',
      );
      expect(
        formatClock(DateTime(2026, 1, 1, 12, 0), use24Hour: false),
        '12:00 PM',
      );
      expect(
        formatClock(DateTime(2026, 1, 1, 13, 5), use24Hour: false),
        '1:05 PM',
      );
      expect(
        formatClock(DateTime(2026, 1, 1, 23, 9), use24Hour: false),
        '11:09 PM',
      );
    });
  });

  group('StatusStripLeftState.pulseAlphaAt (DESIGN.md 6.9)', () {
    test('is 0.5 Hz: one full cycle every 2 s', () {
      final a = StatusStripLeftState.pulseAlphaAt(0);
      final b = StatusStripLeftState.pulseAlphaAt(2);
      expect(a, closeTo(b, 1e-9));
    });

    test(
      'reaches its max a quarter cycle in, and its min three quarters in',
      () {
        // hz = 0.5, period = 2 s; sin peaks at t = period/4 = 0.5 s.
        expect(StatusStripLeftState.pulseAlphaAt(0.5), closeTo(1.0, 1e-9));
        expect(StatusStripLeftState.pulseAlphaAt(1.5), closeTo(0.35, 1e-9));
      },
    );

    test('never leaves its 0.35-1.0 band', () {
      for (var t = 0.0; t < 4; t += 0.1) {
        final a = StatusStripLeftState.pulseAlphaAt(t);
        expect(a, greaterThanOrEqualTo(0.35 - 1e-9));
        expect(a, lessThanOrEqualTo(1.0 + 1e-9));
      }
    });
  });

  group('glyphColumnWidth (DESIGN.md 6.9)', () {
    test(
      'is just the glyph in Motion, and a wider caption column when parked',
      () {
        expect(glyphColumnWidth(0), 20);
        expect(glyphColumnWidth(1), greaterThan(20));
        // Partway between: the columns part on the share, not in a jump.
        final mid = glyphColumnWidth(0.5);
        expect(mid, greaterThan(20));
        expect(mid, lessThan(glyphColumnWidth(1)));
      },
    );
  });

  group('drawing', () {
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

    Future<Uint32List> pixels(WidgetTester tester) async {
      final image = await renderImage(tester);
      late ByteData data;
      await tester.runAsync(() async => data = (await image.toByteData())!);
      return Uint32List.fromList([
        for (var i = 0; i < image.width * image.height; i++)
          data.getUint32(i * 4),
      ]);
    }

    // Ion livery literals, the same ones bar_gauge_test.dart and
    // eco_bar_test.dart use: caution and accent.core are not livery-scoped
    // per-component, so the same hex reliably identifies them here too.
    const cautionArgb = 0xFFB020FF;
    const accentCoreArgb = 0x5CE1FFFF;

    Future<GlobalKey<StatusStripLeftState>> showLeft(
      WidgetTester tester, {
      required ValueNotifier<AdapterLinkState> adapter,
      required ValueNotifier<bool> gpsHasFix,
      ValueNotifier<double>? parkedShare,
    }) async {
      setWindow(tester, const Size(200, 60));
      final key = GlobalKey<StatusStripLeftState>();
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ion),
          child: Center(
            child: StatusStripLeft(
              key: key,
              adapter: adapter,
              gpsHasFix: gpsHasFix,
              parkedShare: parkedShare ?? ValueNotifier(0),
            ),
          ),
        ),
      );
      return key;
    }

    testWidgets('the lost adapter is caution-coloured', (tester) async {
      final adapter = ValueNotifier(AdapterLinkState.lost);
      addTearDown(adapter.dispose);
      final gps = ValueNotifier(false);
      addTearDown(gps.dispose);
      await showLeft(tester, adapter: adapter, gpsHasFix: gps);
      await tester.pump();

      expect(
        (await pixels(tester)).where((v) => v == cautionArgb).length,
        greaterThan(5),
      );
    });

    testWidgets('flowing is not caution-coloured', (tester) async {
      final adapter = ValueNotifier(AdapterLinkState.flowing);
      addTearDown(adapter.dispose);
      final gps = ValueNotifier(true);
      addTearDown(gps.dispose);
      await showLeft(tester, adapter: adapter, gpsHasFix: gps);
      await tester.pump();

      expect((await pixels(tester)).where((v) => v == cautionArgb).length, 0);
    });

    testWidgets(
      'a live change from lost to flowing repaints, no rebuild needed',
      (tester) async {
        // The same shape of regression the eco bar, the telemetry tile and the
        // bar gauge's shouldRepaint already caught: this checks it directly
        // for the status strip too, rather than assuming the pattern holds.
        final adapter = ValueNotifier(AdapterLinkState.lost);
        addTearDown(adapter.dispose);
        final gps = ValueNotifier(false);
        addTearDown(gps.dispose);
        await showLeft(tester, adapter: adapter, gpsHasFix: gps);
        await tester.pump();
        expect(
          (await pixels(tester)).where((v) => v == cautionArgb).length,
          greaterThan(5),
        );

        adapter.value = AdapterLinkState.flowing;
        await tester.pump();
        expect((await pixels(tester)).where((v) => v == cautionArgb).length, 0);
      },
    );

    testWidgets(
      'a swapped adapter ValueListenable repaints, not just a new value',
      (tester) async {
        final adapter = ValueNotifier(AdapterLinkState.flowing);
        addTearDown(adapter.dispose);
        final gps = ValueNotifier(true);
        addTearDown(gps.dispose);
        await showLeft(tester, adapter: adapter, gpsHasFix: gps);
        await tester.pump();
        expect((await pixels(tester)).where((v) => v == cautionArgb).length, 0);

        final other = ValueNotifier(AdapterLinkState.lost);
        addTearDown(other.dispose);
        await showLeft(tester, adapter: other, gpsHasFix: gps);
        await tester.pump();

        expect(
          (await pixels(tester)).where((v) => v == cautionArgb).length,
          greaterThan(5),
        );
      },
    );

    testWidgets('captions are absent in Motion and present when parked', (
      tester,
    ) async {
      // renderImage captures the whole fixed test window, which is the same
      // size either way, so the check is not the image's own dimensions but
      // how much of it is actually drawn on: a parked share of 1 adds
      // caption text on top of the same glyphs, so it lights strictly more
      // pixels.
      int litCount(Uint32List frame) => frame.where((p) {
        final r = (p >> 24) & 0xFF;
        final g = (p >> 16) & 0xFF;
        final b = (p >> 8) & 0xFF;
        return r > 80 || g > 80 || b > 80; // well above the void's grain.
      }).length;

      final adapter = ValueNotifier(AdapterLinkState.lost);
      addTearDown(adapter.dispose);
      final gps = ValueNotifier(false);
      addTearDown(gps.dispose);

      await showLeft(tester, adapter: adapter, gpsHasFix: gps);
      await tester.pump();
      final motionLit = litCount(await pixels(tester));

      final share = ValueNotifier(1.0);
      addTearDown(share.dispose);
      await showLeft(
        tester,
        adapter: adapter,
        gpsHasFix: gps,
        parkedShare: share,
      );
      await tester.pump();
      final parkedLit = litCount(await pixels(tester));

      expect(parkedLit, greaterThan(motionLit));
    });

    group('cost (the search pulse)', () {
      testWidgets('flowing costs the motion clock nothing', (tester) async {
        final adapter = ValueNotifier(AdapterLinkState.flowing);
        addTearDown(adapter.dispose);
        final gps = ValueNotifier(true);
        addTearDown(gps.dispose);
        await showLeft(tester, adapter: adapter, gpsHasFix: gps);
        await tester.pump();

        expect(motion.attachedCount, 0);
      });

      testWidgets('searching attaches, and lost or flowing detaches again', (
        tester,
      ) async {
        final adapter = ValueNotifier(AdapterLinkState.searching);
        addTearDown(adapter.dispose);
        final gps = ValueNotifier(false);
        addTearDown(gps.dispose);
        await showLeft(tester, adapter: adapter, gpsHasFix: gps);
        await tester.pump();
        expect(motion.attachedCount, greaterThan(0));

        adapter.value = AdapterLinkState.flowing;
        await tester.pump();
        expect(motion.attachedCount, 0);
      });
    });

    testWidgets('the DEMO badge shows only when Demo Mode is on', (
      tester,
    ) async {
      setWindow(tester, const Size(300, 60));
      final time = ValueNotifier(DateTime(2026, 1, 1, 10, 0));
      addTearDown(time.dispose);
      final phoneHot = ValueNotifier(false);
      addTearDown(phoneHot.dispose);

      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ion),
          child: Center(
            child: StatusStripRight(
              time: time,
              use24Hour: true,
              phoneHot: phoneHot,
              parkedShare: ValueNotifier(0),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        (await pixels(tester)).where((v) => v == accentCoreArgb).length,
        0,
      );

      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ion),
          child: Center(
            child: StatusStripRight(
              time: time,
              use24Hour: true,
              phoneHot: phoneHot,
              parkedShare: ValueNotifier(0),
              demoMode: true,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        (await pixels(tester)).where((v) => v == accentCoreArgb).length,
        greaterThan(5),
      );
    });

    testWidgets('the clock repaints on a live tick with no rebuild', (
      tester,
    ) async {
      setWindow(tester, const Size(200, 60));
      final time = ValueNotifier(DateTime(2026, 1, 1, 9, 5));
      addTearDown(time.dispose);
      final phoneHot = ValueNotifier(false);
      addTearDown(phoneHot.dispose);
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ion),
          child: Center(
            child: StatusStripRight(
              time: time,
              use24Hour: true,
              phoneHot: phoneHot,
              parkedShare: ValueNotifier(0),
            ),
          ),
        ),
      );
      await tester.pump();
      final before = await pixels(tester);

      time.value = DateTime(2026, 1, 1, 9, 6);
      await tester.pump();
      final after = await pixels(tester);

      expect(before, isNot(equals(after)));
    });

    testWidgets('the flank sits against its right edge, whatever it holds', (
      tester,
    ) async {
      setWindow(tester, const Size(320, 60));
      final time = ValueNotifier(DateTime(2026, 1, 1, 10, 0));
      addTearDown(time.dispose);
      final phoneHot = ValueNotifier(false);
      addTearDown(phoneHot.dispose);
      for (final demo in [false, true]) {
        await tester.pumpWidget(
          tapeHarness(
            kit: kit,
            motion: motion,
            theme: TapeThemeData(livery: Liveries.ion),
            child: Align(
              alignment: Alignment.topRight,
              child: StatusStripRight(
                time: time,
                use24Hour: true,
                phoneHot: phoneHot,
                parkedShare: ValueNotifier(0),
                demoMode: demo,
              ),
            ),
          ),
        );
        await tester.pump();
        final px = await pixels(tester);
        var maxX = -1;
        for (var i = 0; i < px.length; i++) {
          if (px[i] != 0 && (px[i] & 0xFF) != 0 && (px[i] >> 24) > 24) {
            final x = i % 640;
            if (x > maxX) maxX = x;
          }
        }
        // Drawn, and inside the frame, against the right edge (640 px).
        expect(maxX, greaterThan(640 - 16), reason: 'demo=$demo');
        expect(maxX, lessThan(640), reason: 'demo=$demo');
      }
    });
  });
}
