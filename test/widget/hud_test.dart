// The HUD (DESIGN.md 8): the settings' own rules, the mirror, the one-colour
// black canvas, the three layouts at the three screen sizes, the alignment
// pattern flipped with the HUD, the double-tap that toggles it, and the dock
// button.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/tokens/colors.dart';
import 'package:tapedash/ui/design/tokens/hud.dart';
import 'package:tapedash/ui/hud/hud_host.dart';
import 'package:tapedash/ui/hud/hud_settings.dart';
import 'package:tapedash/ui/hud/hud_view.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/ui/pages/strip/parked_dock.dart';
import 'package:tapedash/ui/pages/strip/placeholder_page.dart';
import 'package:tapedash/ui/pages/strip/the_strip.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;
  late VehicleState vehicle;
  late DriveSignals signals;
  late HudSettings settings;
  var feedSpeed = 88.0;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock()..advance(const Duration(seconds: 100));
    vehicle = VehicleState(clock: clock, scheduler: clock);
    signals = DriveSignals(
      vehicle: vehicle,
      motion: motion,
      clock: clock,
      scheduler: clock,
      connection: ObservableValue(ConnectionStatus.connected),
    );
    settings = HudSettings(active: true);
    feedSpeed = 88;
  });

  tearDown(() {
    settings.dispose();
    signals.dispose();
    motion.dispose();
    kit.dispose();
  });

  void ingest(Sensor sensor, double value) {
    final now = clock.monotonic();
    vehicle.ingest(sensor, value, at: now, receivedAt: now);
  }

  void feed(double rpm) {
    ingest(Sensor.speed, feedSpeed);
    ingest(Sensor.rpm, rpm);
  }

  /// Steps the clocks, with a fresh reading every 100 ms when [feeding] is an
  /// rpm: stale values are dimmed on purpose, and what these tests look at is
  /// the live HUD.
  void run(Duration duration, {double? feeding}) {
    var left = duration.inMicroseconds;
    var sinceFeed = 0;
    const frame = 16667;
    while (left > 0) {
      final step = left < frame ? left : frame;
      sinceFeed += step;
      if (feeding != null && sinceFeed >= 100000) {
        sinceFeed = 0;
        feed(feeding);
      }
      motion.tick(step / 1e6);
      clock.advance(Duration(microseconds: step));
      left -= step;
    }
  }

  Future<void> show(WidgetTester tester, Size size) async {
    setWindow(tester, size);
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: HudView(
          signals: signals,
          settings: settings,
          width: size.width,
          height: size.height,
        ),
      ),
    );
    feed(2400);
    run(const Duration(seconds: 2), feeding: 2400);
    await tester.pump();
  }

  Future<Uint32List> pixels(WidgetTester tester) async {
    final image = await renderImage(tester);
    late ByteData data;
    await tester.runAsync(() async => data = (await image.toByteData())!);
    return Uint32List.fromList([
      for (var i = 0; i < image.width * image.height; i++)
        data.getUint32(i * 4),
    ]);
  }

  int red(int p) => (p >> 24) & 0xFF;
  int green(int p) => (p >> 16) & 0xFF;
  int blue(int p) => (p >> 8) & 0xFF;
  bool lit(int p) => red(p) + green(p) + blue(p) > 60;

  group('the settings (DESIGN.md 8)', () {
    test('default to a green HUD, flipped horizontally, not up', () {
      final s = HudSettings();
      expect(s.color, HudColor.green);
      expect(s.flipHorizontal, isTrue);
      expect(s.flipVertical, isFalse);
      expect(s.active, isFalse);
      expect(s.layout, HudLayout.drive);
      s.dispose();
    });

    test('position and scale are clamped to their sliders', () {
      final s = HudSettings()
        ..verticalPosition = 5
        ..scale = 9;
      expect(s.verticalPosition, 1);
      expect(s.scale, TapeHud.scaleMax);
      s
        ..verticalPosition = -5
        ..scale = 0;
      expect(s.verticalPosition, -1);
      expect(s.scale, TapeHud.scaleMin);
      s.dispose();
    });

    test('toggle, and the pattern brings the HUD up and down with it', () {
      final s = HudSettings();
      var notified = 0;
      s.addListener(() => notified++);
      s.toggle();
      expect(s.active, isTrue);
      s.showAlignment = true;
      expect(s.showAlignment, isTrue);
      s.active = false;
      expect(s.showAlignment, isFalse);
      s.showAlignment = true;
      expect(s.active, isTrue);
      final before = notified;
      s.showAlignment = true;
      expect(notified, before);
      s.dispose();
    });
  });

  group('the mirror', () {
    Offset through(HudSettings s, Offset p) =>
        MatrixUtils.transformPoint(HudView.transformFor(s, 400), p);

    test('flip horizontal mirrors x, keeps y', () {
      final s = HudSettings();
      expect(through(s, const Offset(10, 20)), const Offset(-10, 20));
      s.dispose();
    });

    test('flip vertical mirrors y', () {
      final s = HudSettings(flipHorizontal: false, flipVertical: true);
      expect(through(s, const Offset(10, 20)), const Offset(10, -20));
      s.dispose();
    });

    test('a raised position moves the content up in its own space', () {
      final s = HudSettings(flipHorizontal: false, verticalPosition: 1);
      // Up is a smaller y: by the reach's share of the height.
      expect(
        through(s, const Offset(0, 0)).dy,
        closeTo(-TapeHud.positionReach * 400, 1e-9),
      );
      // With the vertical flip on it is the same shift, then mirrored: what
      // the driver sees moves up whichever way the phone is placed.
      s.flipVertical = true;
      expect(
        through(s, const Offset(0, 0)).dy,
        closeTo(TapeHud.positionReach * 400, 1e-9),
      );
      s.dispose();
    });

    test('scale scales both axes', () {
      final s = HudSettings(flipHorizontal: false, scale: 1.2);
      final p = through(s, const Offset(10, 10));
      expect(p.dx, closeTo(12, 1e-9));
      expect(p.dy, closeTo(12, 1e-9));
      s.dispose();
    });
  });

  group('the canvas: black and one colour', () {
    for (final size in const [Size(640, 360), Size(720, 360), Size(800, 360)]) {
      for (final layout in HudLayout.values) {
        testWidgets('${layout.name} at ${size.width.toInt()}x360', (
          tester,
        ) async {
          settings.layout = layout;
          await show(tester, size);
          final px = await pixels(tester);
          final hud = HudColor.green.color;
          final maxR = (hud.r * 255).round() + 2;
          final maxG = (hud.g * 255).round() + 2;
          final maxB = (hud.b * 255).round() + 2;
          var litCount = 0;
          for (final p in px) {
            expect(red(p), lessThanOrEqualTo(maxR));
            expect(green(p), lessThanOrEqualTo(maxG));
            expect(blue(p), lessThanOrEqualTo(maxB));
            if (lit(p)) litCount++;
          }
          expect(litCount, greaterThan(px.length ~/ 200));
          // Pure black where nothing is drawn: the corners.
          expect(px.first & 0xFFFFFF00, 0);
          expect(px.last & 0xFFFFFF00, 0);
          // And no large filled areas (DESIGN.md 8): under a quarter lit.
          expect(litCount, lessThan(px.length ~/ 4));
        });
      }
    }

    testWidgets('the speed is centred on its own ink, whatever its digits', (
      tester,
    ) async {
      settings.flipHorizontal = false;
      await show(tester, const Size(720, 360));
      for (final speed in [64, 88, 11, 100]) {
        final now = clock.monotonic();
        vehicle.ingest(
          Sensor.speed,
          speed.toDouble(),
          at: now,
          receivedAt: now,
        );
        run(const Duration(seconds: 2), feeding: 2400);
        ingest(Sensor.speed, speed.toDouble());
        run(const Duration(seconds: 1));
        await tester.pump();
        final px = await pixels(tester);
        // The numeral's own rows, clear of the label and the bar.
        var lo = 1 << 30, hi = -1;
        for (var y = 100; y < 480; y++) {
          for (var x = 0; x < 1440; x++) {
            if (lit(px[y * 1440 + x])) {
              if (x < lo) lo = x;
              if (x > hi) hi = x;
            }
          }
        }
        // Three digits at 100 read a little left of centre by design (the
        // reservation overflows left); one or two are centred to the pixel.
        expect(
          (lo + hi) / 2,
          closeTo(720, speed >= 100 ? 140 : 12),
          reason: '$speed',
        );
      }
    });

    testWidgets('the colour follows the setting', (tester) async {
      settings.color = HudColor.amber;
      await show(tester, const Size(720, 360));
      var px = await pixels(tester);
      final peak = px.reduce((a, b) => green(a) > green(b) ? a : b);
      expect(red(peak), closeTo(0xFF, 3));
      expect(blue(peak), lessThan(0x40));

      settings.color = HudColor.ion;
      await tester.pump();
      run(const Duration(milliseconds: 100));
      await tester.pump();
      px = await pixels(tester);
      final ion = px.reduce((a, b) => blue(a) > blue(b) ? a : b);
      expect(blue(ion), closeTo(0xFF, 3));
      expect(red(ion), lessThan(0x70));
    });

    testWidgets('a redline rpm is critical and stands taller', (tester) async {
      await show(tester, const Size(720, 360));
      final calm = await pixels(tester);
      feed(7500);
      run(const Duration(seconds: 2), feeding: 7500);
      await tester.pump();
      final hot = await pixels(tester);
      bool reddish(int p) => red(p) > 200 && green(p) < 90;
      expect(calm.where(reddish), isEmpty);
      expect(hot.where(reddish).length, greaterThan(50));
    });

    test('the bar is lit as rpm over its scale, and no more', () {
      expect(HudRpmBarPainter.litShare(0), 0);
      expect(HudRpmBarPainter.litShare(TapeHud.rpmMax / 2), 0.5);
      expect(HudRpmBarPainter.litShare(TapeHud.rpmMax * 2), 1);
      expect(HudRpmBarPainter.litShare(-100), 0);
    });
  });

  group('money is honestly absent until phase 4', () {
    testWidgets('Drive + Money and Money say so, and show no ₹ figure', (
      tester,
    ) async {
      settings.layout = HudLayout.money;
      await show(tester, const Size(720, 360));
      expect(find.text('MONEY UNAVAILABLE'), findsOneWidget);
      settings.layout = HudLayout.driveMoney;
      await tester.pump();
      expect(find.text('MONEY UNAVAILABLE'), findsOneWidget);
      expect(find.text('KM/H'), findsOneWidget);
    });
  });

  group('the alignment pattern', () {
    // The F is to the left of the crosshair and the arrow with UP to its
    // right, so ink to the left against ink to the right tells which way the
    // pattern (and so the HUD) is mirrored.
    int band(Uint32List px, int w, int h, double x0, double x1) {
      var n = 0;
      for (var y = (h * 0.25).round(); y < (h * 0.75).round(); y++) {
        for (var x = (w * x0).round(); x < (w * x1).round(); x++) {
          if (lit(px[y * w + x])) n++;
        }
      }
      return n;
    }

    testWidgets('is drawn through the HUD\'s own flips', (tester) async {
      settings
        ..flipHorizontal = false
        ..showAlignment = true;
      await show(tester, const Size(720, 360));
      var px = await pixels(tester);
      const w = 1440, h = 720;
      final leftPlain = band(px, w, h, 0.05, 0.30);
      final rightPlain = band(px, w, h, 0.70, 0.95);
      expect(leftPlain, greaterThan(rightPlain));

      settings.flipHorizontal = true;
      await tester.pump();
      run(const Duration(milliseconds: 100));
      await tester.pump();
      px = await pixels(tester);
      final leftFlipped = band(px, w, h, 0.05, 0.30);
      final rightFlipped = band(px, w, h, 0.70, 0.95);
      expect(rightFlipped, greaterThan(leftFlipped));
      expect(rightFlipped, closeTo(leftPlain, leftPlain * 0.05));
    });

    testWidgets('carries the wordmark, the F and UP', (tester) async {
      settings.showAlignment = true;
      await show(tester, const Size(720, 360));
      expect(find.text('TAPEDASH'), findsOneWidget);
      expect(find.text('F'), findsOneWidget);
      expect(find.text('UP'), findsOneWidget);
    });
  });

  group('toggling', () {
    testWidgets('a double-tap on Drive or Money calls it; Coach does not', (
      tester,
    ) async {
      setWindow(tester, const Size(800, 400));
      var toggles = 0;
      final mode = ValueNotifier(DrivingMode.parked);
      addTearDown(mode.dispose);
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          child: TheStrip(
            pages: [
              for (final n in ['REVIEW', 'MONEY', 'DRIVE', 'COACH', 'HISTORY'])
                StripPlaceholder(
                  name: n,
                  note: 'Later.',
                  width: 800,
                  height: 400,
                ),
            ],
            mode: mode,
            motion: motion,
            width: 800,
            height: 400,
            onToggleHud: () => toggles++,
          ),
        ),
      );
      Future<void> doubleTap() async {
        await tester.tapAt(const Offset(400, 200));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(const Offset(400, 200));
        await tester.pump();
      }

      await doubleTap();
      expect(toggles, 1);

      final state = tester.state<TheStripState>(find.byType(TheStrip));
      expect(state.offset, TheStrip.homePage.toDouble());
      // Move to Coach (parked: reachable) and try again.
      await tester.timedDrag(
        find.byType(TheStrip),
        const Offset(-500, 0),
        const Duration(milliseconds: 200),
      );
      run(const Duration(seconds: 2));
      await tester.pump();
      expect(state.offset.round(), greaterThan(TheStrip.homePage));
      await doubleTap();
      expect(toggles, 1);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the host puts the HUD up and a double-tap puts it down', (
      tester,
    ) async {
      setWindow(tester, const Size(720, 360));
      settings.active = false;
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          child: HudHost(
            settings: settings,
            signals: signals,
            width: 720,
            height: 360,
            child: const SizedBox.expand(),
          ),
        ),
      );
      expect(find.byType(HudView), findsNothing);
      settings.toggle();
      await tester.pump();
      expect(find.byType(HudView), findsOneWidget);

      await tester.tapAt(const Offset(360, 180));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(const Offset(360, 180));
      await tester.pump();
      expect(settings.active, isFalse);
      expect(find.byType(HudView), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the dock\'s HUD button calls it, the rest stay disabled', (
      tester,
    ) async {
      setWindow(tester, const Size(800, 400));
      var hud = 0;
      final mode = ValueNotifier(DrivingMode.parked);
      addTearDown(mode.dispose);
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          child: ParkedDock(
            mode: mode,
            motion: motion,
            width: 800,
            height: 400,
            onHud: () => hud++,
          ),
        ),
      );
      run(const Duration(milliseconds: 900));
      await tester.pump();
      await tester.tap(find.text('HUD'));
      await tester.pump();
      expect(hud, 1);
      await tester.tap(find.text('GARAGE'));
      await tester.pump();
      expect(hud, 1);
      expect(find.byType(TapeButton), findsNWidgets(4));
    });
  });
}
