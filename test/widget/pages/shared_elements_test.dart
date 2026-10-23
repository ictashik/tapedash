// The shared-element transition (DESIGN.md 7.1): the flight math, the
// presence plumbing, the flight itself mid-swipe, and the landings at both
// ends. Flight tests run against a real SimDrive with the Strip and the
// Money page, the same rig the strip's own tests use.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/centered_numeral.dart';
import 'package:tapedash/ui/design/components/rolling_numerals.dart';
import 'package:tapedash/ui/design/components/shared_element_end.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/shared_elements.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/ui/pages/drive/drive_page.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/ui/pages/money/money_page.dart';
import 'package:tapedash/ui/pages/strip/placeholder_page.dart';
import 'package:tapedash/ui/pages/strip/the_strip.dart';
import 'package:tapedash/vehicle/vehicle_state.dart' show DrivingMode;

import '../../design/support/harness.dart';
import '../../design/support/numbers.dart';
import '../../support/sim_drive.dart';

void main() {
  setUpAll(loadTapeFonts);

  group('the flight math (DESIGN.md 7.1)', () {
    test('flightOf is 0 at the from page and 1 at the to page', () {
      final f = SharedElementsController.flightOf;
      expect(f(2, fromPage: 2, toPage: 1), 0);
      expect(f(1, fromPage: 2, toPage: 1), 1);
      expect(f(1.5, fromPage: 2, toPage: 1), closeTo(0.5, 1e-9));
      // Clamped past either end.
      expect(f(3, fromPage: 2, toPage: 1), 0);
      expect(f(0, fromPage: 2, toPage: 1), 1);
    });

    test('the from end\'s own copy is gone by the depart share', () {
      final f = SharedElementsController.fromEndOwnShare;
      expect(f(0), 1);
      expect(f(TapeMotion.sharedElementDepart / 2), closeTo(0.5, 1e-9));
      expect(f(TapeMotion.sharedElementDepart), closeTo(0, 1e-9));
      expect(f(1), 0);
    });

    test('the to end\'s own copy appears only from the arrive share', () {
      final f = SharedElementsController.toEndOwnShare;
      expect(f(0), 0);
      expect(f(TapeMotion.sharedElementArrive), closeTo(0, 1e-9));
      final mid = (TapeMotion.sharedElementArrive + 1) / 2;
      expect(f(mid), closeTo(0.5, 1e-9));
      expect(f(1), 1);
    });

    test('rectAt lerps the element\'s rect between the two ends', () {
      final from = Rect.fromLTWH(100, 200, 50, 30);
      final to = Rect.fromLTWH(700, 20, 30, 20);
      expect(
        SharedElementsController.rectAt(0, from, to).topLeft,
        from.topLeft,
      );
      expect(SharedElementsController.rectAt(1, from, to).topLeft, to.topLeft);
      final half = SharedElementsController.rectAt(0.5, from, to);
      expect(half.center.dx, closeTo(420, 1e-9));
      expect(half.center.dy, closeTo(122.5, 1e-9));
    });

    test('scaleAt lerps between the from end\'s scale and the to share', () {
      final s = SharedElementsController.scaleAt;
      expect(s(0, 1, 0.3), closeTo(1, 1e-9));
      expect(s(1, 1, 0.3), closeTo(0.3, 1e-9));
      expect(s(0.5, 1, 0.3), closeTo(0.65, 1e-9));
      expect(s(0, 0.6, 0.3), closeTo(0.6, 1e-9));
    });
  });

  group('the presence plumbing', () {
    late TapeRenderKit kit;
    late ManualMotionClock motion;
    setUp(() {
      kit = TapeRenderKit();
      motion = ManualMotionClock();
    });
    tearDown(() {
      kit.dispose();
      motion.dispose();
    });

    const format3 = NumeralFormat(integerDigits: 3);

    for (final livery in [Liveries.ion, Liveries.vfd]) {
      testWidgets('presence 1 shows and 0 hides the numerals ($livery)', (
        tester,
      ) async {
        setWindow(tester, const Size(640, 360));
        final n = ManualNumber(88);
        final presence = ValueNotifier<double>(1);
        addTearDown(n.dispose);
        addTearDown(presence.dispose);
        await tester.pumpWidget(
          tapeHarness(
            kit: kit,
            motion: motion,
            theme: TapeThemeData(livery: livery),
            child: Align(
              child: RollingNumerals(
                source: n,
                format: format3,
                size: 60,
                role: NumeralRole.bright,
                presence: presence,
              ),
            ),
          ),
        );
        // The VFD renderer's phosphor needs a tick of the clock to rise.
        motion.tick(0.2);
        await tester.pump();

        Future<int> ink() async => _brightCount(await _pixelsOf(tester));

        expect(await ink(), greaterThan(0), reason: 'no ink at presence 1');
        presence.value = 0;
        await tester.pump();
        expect(await ink(), 0, reason: 'ink remains at presence 0');
      });
    }
  });

  group('the flight between Drive and Money', () {
    late TapeRenderKit kit;
    late ManualMotionClock motion;
    late FakeClock clock;
    late DriveSignals signals;
    late SimDrive demo;

    setUp(() {
      kit = TapeRenderKit();
      motion = ManualMotionClock();
      clock = FakeClock()..advance(const Duration(seconds: 100));
      demo = SimDrive(
        clock: clock,
        scheduler: clock,
        scenario: 'highway_cruise',
        profile: 'petrol_cvt_maf',
      );
      demo.start();
      signals = DriveSignals(
        vehicle: demo.vehicle,
        motion: motion,
        clock: clock,
        scheduler: clock,
        connection: demo.connection,
      );
    });

    tearDown(() {
      demo.stop();
      signals.dispose();
      motion.dispose();
      kit.dispose();
    });

    void run(Duration duration) {
      var left = duration.inMicroseconds;
      const frame = 16667;
      while (left > 0) {
        final step = left < frame ? left : frame;
        motion.tick(step / 1e6);
        clock.advance(Duration(microseconds: step));
        left -= step;
      }
    }

    Widget strip(ValueNotifier<DrivingMode> mode, {Widget? moneyPage}) =>
        TheStrip(
          pages: [
            StripPlaceholder(
              name: 'REVIEW',
              note: 'Arrives later.',
              width: 800,
              height: 400,
            ),
            moneyPage ?? MoneyPage(signals: signals, width: 800, height: 400),
            DrivePage(
              signals: signals,
              motion: motion,
              width: 800,
              height: 400,
            ),
            StripPlaceholder(
              name: 'COACH',
              note: 'Arrives later.',
              width: 800,
              height: 400,
            ),
            StripPlaceholder(
              name: 'HISTORY',
              note: 'Arrives later.',
              width: 800,
              height: 400,
            ),
          ],
          mode: mode,
          motion: motion,
          width: 800,
          height: 400,
        );

    Future<void> pumpStrip(
      WidgetTester tester,
      ValueNotifier<DrivingMode> mode,
    ) async {
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ion),
          child: strip(mode),
        ),
      );
      run(const Duration(seconds: 15));
      await tester.pump();
    }

    /// The presence share a cluster's hero readout was built with, for the
    /// strip the page is inside.
    double heroPresence(WidgetTester tester) => tester
        .widget<CenteredNumeral>(
          find
              .descendant(
                of: find.descendant(
                  of: find.byType(DrivePage),
                  matching: find.byType(SharedElementEnd),
                ),
                matching: find.byType(CenteredNumeral),
              )
              .first,
        )
        .presence!
        .value;

    double cornerPresence(WidgetTester tester) => tester
        .widget<CenteredNumeral>(
          find
              .descendant(
                of: find.byType(MoneyPage),
                matching: find.byType(CenteredNumeral),
              )
              .first,
        )
        .presence!
        .value;

    testWidgets('the travelling copy carries the number mid-swipe', (
      tester,
    ) async {
      setWindow(tester, const Size(800, 400));
      final mode = ValueNotifier(DrivingMode.parked);
      addTearDown(mode.dispose);
      await pumpStrip(tester, mode);

      // At rest, the hero's own copy is fully present.
      expect(heroPresence(tester), 1);

      // A held drag halfway to Money: the finger stays down so the raw sits
      // at 1.5 and the spring settles there; the flight is at t = 0.5.
      final drag = await tester.startGesture(const Offset(400, 200));
      await drag.moveBy(const Offset(200, 0));
      run(const Duration(milliseconds: 40));
      await drag.moveBy(const Offset(200, 0));
      run(const Duration(milliseconds: 700));
      await tester.pump();
      await tester.pump();

      // The element's flight path between the hero and the corner: the
      // travelling copy is the bright ink in that corridor.
      final frame = await _pixelsOf(tester);
      expect(
        _brightIn(frame, w: 1600, rect: Rect.fromLTWH(360, 20, 400, 180)),
        greaterThan(0),
        reason: 'no travelling copy mid-swipe',
      );
      // The hero's own copy has left (depart ramp done by t = 0.5).
      expect(heroPresence(tester), closeTo(0, 1e-9));
      // The corner's own copy has not arrived (arrive ramp not started).
      expect(cornerPresence(tester), closeTo(0, 1e-9));

      await drag.cancel();
    });

    testWidgets('the Money corner appears when the element arrives', (
      tester,
    ) async {
      setWindow(tester, const Size(800, 400));
      final mode = ValueNotifier(DrivingMode.parked);
      addTearDown(mode.dispose);
      await pumpStrip(tester, mode);

      // Held mid-swipe: the corner's own copy is still hidden.
      final drag = await tester.startGesture(const Offset(400, 200));
      await drag.moveBy(const Offset(200, 0));
      run(const Duration(milliseconds: 40));
      await drag.moveBy(const Offset(200, 0));
      run(const Duration(milliseconds: 700));
      await tester.pump();
      await tester.pump();
      expect(cornerPresence(tester), closeTo(0, 1e-9));

      // A cancelled drag settles back to Drive (the nearest page to the
      // held 1.5), then a fling to Money: the tester's flingFrom avoids the
      // nested gesture-arena interaction between the strip's horizontal drag
      // and the DrivePage's vertical reel.
      await drag.cancel();
      run(const Duration(seconds: 1));
      await tester.pump();
      await tester.flingFrom(
        const Offset(400, 200),
        const Offset(800, 200),
        300,
      );
      run(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(cornerPresence(tester), 1);
      final frame = await _pixelsOf(tester);
      expect(
        _brightIn(frame, w: 1600, rect: Rect.fromLTWH(700, 12, 90, 70)),
        greaterThan(0),
        reason: 'no speed in the Money corner after settling',
      );
    });

    testWidgets('a swipe reversed mid-flight lands back with the hero full', (
      tester,
    ) async {
      setWindow(tester, const Size(800, 400));
      final mode = ValueNotifier(DrivingMode.parked);
      addTearDown(mode.dispose);
      await pumpStrip(tester, mode);

      final drag = await tester.startGesture(const Offset(400, 200));
      await drag.moveBy(const Offset(300, 0));
      run(const Duration(milliseconds: 120));
      await drag.moveBy(const Offset(-300, 0));
      run(const Duration(milliseconds: 120));
      // Cancelling (rather than releasing) settles to the nearest page with
      // no release velocity to carry the landing anywhere else.
      await drag.cancel();
      run(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump();

      expect(heroPresence(tester), 1);
      final frame = await _pixelsOf(tester);
      expect(
        _brightIn(frame, w: 1600, rect: Rect.fromLTWH(280, 120, 240, 160)),
        greaterThan(0),
        reason: 'hero not restored after the reversal',
      );
    });

    testWidgets('the pages do not rebuild while the flight moves', (
      tester,
    ) async {
      setWindow(tester, const Size(800, 400));
      final mode = ValueNotifier(DrivingMode.parked);
      addTearDown(mode.dispose);
      var moneyBuilds = 0;
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ion),
          child: strip(
            mode,
            moneyPage: Builder(
              builder: (context) {
                moneyBuilds++;
                return MoneyPage(signals: signals, width: 800, height: 400);
              },
            ),
          ),
        ),
      );
      run(const Duration(seconds: 15));
      await tester.pump();
      moneyBuilds = 0;

      final drag = await tester.startGesture(const Offset(400, 200));
      await drag.moveBy(const Offset(200, 0));
      run(const Duration(milliseconds: 120));
      await drag.moveBy(const Offset(-200, 0));
      run(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump();
      expect(moneyBuilds, 0, reason: 'Money page rebuilt during the swipe');

      await drag.cancel();
    });
  });
}

/// The whole frame as packed `0xRRGGBBAA` pixels (the platform's own byte
/// order, per `toByteData`; see the Road cluster's test comment).
Future<Uint32List> _pixelsOf(WidgetTester tester) async {
  final image = await renderImage(tester);
  late ByteData data;
  await tester.runAsync(() async => data = (await image.toByteData())!);
  return Uint32List.fromList([
    for (var i = 0; i < image.width * image.height; i++) data.getUint32(i * 4),
  ]);
}

/// How many pixels in [rect] (logical, on a frame [w] physical pixels wide
/// from an 800 lp window) are bright: every channel above the dim-text tone,
/// so only full numerals and hot ink count, not labels, etch or the void.
int _brightIn(Uint32List frame, {required int w, required Rect rect}) {
  final scale = w / 800;
  var count = 0;
  final h = frame.length ~/ w;
  for (
    var y = (rect.top * scale).round();
    y < (rect.bottom * scale).round();
    y++
  ) {
    if (y < 0 || y >= h) continue;
    for (
      var x = (rect.left * scale).round();
      x < (rect.right * scale).round();
      x++
    ) {
      if (x < 0 || x >= w) continue;
      if (_isBright(frame[y * w + x])) count++;
    }
  }
  return count;
}

bool _isBright(int v) =>
    ((v >> 24) & 0xFF) > 160 &&
    ((v >> 16) & 0xFF) > 160 &&
    ((v >> 8) & 0xFF) > 160;

int _brightCount(Uint32List frame) {
  var count = 0;
  for (final v in frame) {
    if (_isBright(v)) count++;
  }
  return count;
}
