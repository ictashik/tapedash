// The navigation layout of the HUD (DESIGN.md 8, docs/NAV.md): it takes over while
// Google Maps is guiding, shows the real arrow and Maps' figures in the one colour
// on black, says plainly when Maps has gone quiet, and keeps to the HUD's rules.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_settings.dart';
import 'package:tapedash/app/nav_service.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/nav/nav_arrow.dart';
import 'package:tapedash/nav/nav_bend.dart';
import 'package:tapedash/nav/nav_notification.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/platform/nav_channel.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/tokens/colors.dart';
import 'package:tapedash/ui/design/tokens/hud.dart';
import 'package:tapedash/ui/design/tokens/strokes.dart';
import 'package:tapedash/ui/hud/hud_settings.dart';
import 'package:tapedash/ui/hud/hud_view.dart';
import 'package:tapedash/ui/hud/nav_hud.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../design/support/harness.dart';

NavArrow _real(String id) => NavArrow(
  id: id,
  width: 126,
  height: 126,
  alpha: File('test/fixtures/nav/arrows/$id.alpha').readAsBytesSync(),
);

NavNotification _turn({
  String distance = '650 m',
  String instruction = 'Turn right at Richmond Cir onto Mission Rd',
  String arrow = 'e687a80d8d',
  int progress = 171,
}) => NavNotification(
  title: '$distance · $instruction',
  subText: 'Arrive 9:25 PM',
  shortCriticalText: distance,
  progress: progress,
  progressMax: 6605,
  template: 'android.app.Notification\$ProgressStyle',
  arrow: _real(arrow),
);

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;
  late VehicleState vehicle;
  late DriveSignals signals;
  late HudSettings settings;
  late AppSettings app;
  late FakeNavSource source;
  late NavService nav;

  setUp(() async {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock(start: DateTime(2026, 10, 24, 20, 58))
      ..advance(const Duration(seconds: 100));
    vehicle = VehicleState(clock: clock, scheduler: clock);
    signals = DriveSignals(
      vehicle: vehicle,
      motion: motion,
      clock: clock,
      scheduler: clock,
      connection: ObservableValue(ConnectionStatus.connected),
    );
    settings = HudSettings(active: true);
    app = AppSettings(MemoryKeyValueStore());
    await app.load();
    app.navEnabled.value = true;
    source = FakeNavSource(access: true);
    nav = NavService(
      settings: app,
      source: source,
      clock: clock,
      scheduler: clock,
      speed: vehicle.motion,
    )..start();
  });

  tearDown(() {
    nav.dispose();
    settings.dispose();
    signals.dispose();
    motion.dispose();
    kit.dispose();
  });

  void speed(double kmh) {
    final now = clock.monotonic();
    vehicle.ingest(Sensor.speed, kmh, at: now, receivedAt: now);
  }

  /// Steps the clocks, with a fresh speed every 100 ms.
  void run(Duration duration, {double kmh = 54}) {
    var left = duration.inMicroseconds;
    var since = 1 << 30;
    const frame = 16667;
    while (left > 0) {
      final step = left < frame ? left : frame;
      since += step;
      if (since >= 100000) {
        since = 0;
        speed(kmh);
      }
      motion.tick(step / 1e6);
      clock.advance(Duration(microseconds: step));
      left -= step;
    }
  }

  Future<void> show(
    WidgetTester tester,
    Size size, {
    bool withNav = true,
    HudSettings? hud,
  }) async {
    setWindow(tester, size);
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: HudView(
          signals: signals,
          settings: hud ?? settings,
          width: size.width,
          height: size.height,
          nav: withNav ? nav : null,
        ),
      ),
    );
    run(const Duration(seconds: 2));
    await tester.pump();
  }

  /// Maps says something, and the arrow's image is given a moment to be made.
  Future<void> maps(WidgetTester tester, NavNotification n) async {
    source.push(NavPosted(n));
    // The event, then the HUD built and painted (which asks for the image).
    await tester.pump();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    run(const Duration(milliseconds: 100));
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

  /// How many pixels are lit in [area], given in logical pixels (the render is at
  /// twice that).
  int litIn(Uint32List px, Size size, Rect area) {
    final w = (size.width * 2).round();
    var n = 0;
    for (var y = (area.top * 2).floor(); y < (area.bottom * 2).ceil(); y++) {
      for (var x = (area.left * 2).floor(); x < (area.right * 2).ceil(); x++) {
        if (lit(px[y * w + x])) n++;
      }
    }
    return n;
  }

  group('when it takes over', () {
    testWidgets('only while Maps is guiding', (tester) async {
      await show(tester, const Size(720, 360));
      expect(
        find.byType(NavHud),
        findsNothing,
        reason: 'nothing is navigating',
      );

      await maps(tester, _turn());
      expect(find.byType(NavHud), findsOneWidget);

      source.push(const NavRemoved());
      await tester.pump();
      await tester.pump();
      expect(find.byType(NavHud), findsNothing, reason: 'Maps stopped');
    });

    testWidgets('never with the switch off', (tester) async {
      app.navEnabled.value = false;
      await show(tester, const Size(720, 360));

      source.push(NavPosted(_turn()));
      await tester.pump();

      expect(find.byType(NavHud), findsNothing);
    });

    testWidgets('not at all for a HUD that was given no navigation', (
      tester,
    ) async {
      await show(tester, const Size(720, 360), withNav: false);
      nav.tracker.onNotification(_turn());
      await tester.pump();

      expect(find.byType(NavHud), findsNothing);
    });

    testWidgets('the alignment pattern still comes first', (tester) async {
      await show(tester, const Size(720, 360));
      await maps(tester, _turn());
      expect(find.byType(NavHud), findsOneWidget);

      settings.showAlignment = true;
      await tester.pump();

      expect(find.byType(NavHud), findsNothing);
    });
  });

  group('the canvas: black and one colour', () {
    for (final size in const [Size(640, 360), Size(720, 360), Size(800, 360)]) {
      testWidgets('guiding at ${size.width.toInt()}x360', (tester) async {
        await show(tester, size);
        await maps(tester, _turn());
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
        expect(litCount, greaterThan(px.length ~/ 40));
        // Pure black where nothing is drawn: the corners.
        expect(px.first & 0xFFFFFF00, 0);
        expect(px.last & 0xFFFFFF00, 0);
        // And no large filled areas (DESIGN.md 8): under a quarter lit.
        expect(litCount, lessThan(px.length ~/ 4));
      });
    }

    testWidgets('in the colour that was chosen', (tester) async {
      settings.color = HudColor.ion;
      await show(tester, const Size(720, 360));
      await maps(tester, _turn());
      final px = await pixels(tester);

      final ion = HudColor.ion.color;
      var brightest = 0;
      for (final p in px.where(lit)) {
        brightest = brightest > green(p) ? brightest : green(p);
        expect(red(p), lessThanOrEqualTo((ion.r * 255).round() + 2));
      }
      // Ion is blue-green: green and blue both reach near their full.
      expect(brightest, greaterThan(180));
    });
  });

  group('what is drawn', () {
    const size = Size(720, 360);

    testWidgets('the arrow, in the arrow\'s own place', (tester) async {
      await show(tester, size);
      await maps(tester, _turn());
      final px = await pixels(tester);
      final g = NavHudGeometry(size.width, size.height);
      // The HUD is mirrored by default: what is drawn on the right of the
      // layout is on the left of the screen.
      final mirrored = Rect.fromLTRB(
        size.width - g.arrow.right,
        g.arrow.top,
        size.width - g.arrow.left,
        g.arrow.bottom,
      );

      // A turn arrow is about an eighth of its box in ink.
      expect(litIn(px, size, mirrored), greaterThan(900));
    });

    testWidgets('no arrow where Maps gave none', (tester) async {
      await show(tester, size);
      await maps(
        tester,
        const NavNotification(title: 'Rerouting...', subText: 'Arrive '),
      );
      final px = await pixels(tester);
      final g = NavHudGeometry(size.width, size.height);
      final bottom = Rect.fromLTWH(0, g.figuresY - 30, size.width, 60);

      // Rerouting: Maps' words, and none of its figures.
      expect(litIn(px, size, bottom), 0);
    });

    testWidgets('"0 m" beside a straight arrow shows no distance', (
      tester,
    ) async {
      // Maps 26.42 on a real phone wrote the title "0 m" beside "towards Lavelle
      // Road" and the HUD showed "0 M" over a straight arrow.
      await show(tester, size);
      final g = NavHudGeometry(size.width, size.height);
      final distance = Rect.fromLTRB(
        size.width - g.distanceLeft - g.distanceMaxWidth,
        g.arrow.top,
        size.width - g.distanceLeft,
        g.arrow.bottom,
      );
      NavNotification classic(String title) => NavNotification(
        title: title,
        text: 'towards Lavelle Road',
        subText: '25 min \u00B7 7.5 km \u00B7 9:46\u202Fpm ETA',
        arrow: _real('5c317d6e0e'),
      );

      await maps(tester, classic('120\u00A0m'));
      final with120 = await pixels(tester);
      await maps(tester, classic('0\u00A0m'));
      final with0 = await pixels(tester);

      expect(litIn(with120, size, distance), greaterThan(100));
      expect(litIn(with0, size, distance), 0);
    });

    testWidgets('the figures along the bottom, while guiding', (tester) async {
      await show(tester, size);
      await maps(tester, _turn());
      final px = await pixels(tester);
      final g = NavHudGeometry(size.width, size.height);

      for (final centre in g.figureCentres.take(2)) {
        // The ETA and the time left (no distance left is in this shape's text,
        // but the progress gives it: all three are there).
        final around = Rect.fromCenter(
          center: Offset(size.width - centre, g.figuresY),
          width: 120,
          height: 60,
        );
        expect(litIn(px, size, around), greaterThan(150));
      }
      final third = Rect.fromCenter(
        center: Offset(size.width - g.figureCentres[2], g.figuresY),
        width: 120,
        height: 60,
      );
      expect(litIn(px, size, third), greaterThan(150));
    });

    testWidgets('the line to the junction, and a dot on it', (tester) async {
      await show(tester, size);
      await maps(tester, _turn(distance: '100 m'));
      final px = await pixels(tester);
      final g = NavHudGeometry(size.width, size.height);
      final x = size.width - g.lineX;

      // The line runs up its whole length: lit where it passes.
      for (final y in [g.lineBottom - 4, (g.lineBottom + g.lineTop) / 2]) {
        expect(
          litIn(
            px,
            size,
            Rect.fromCenter(center: Offset(x, y), width: 14, height: 2),
          ),
          greaterThan(5),
          reason: 'the line at y=$y',
        );
      }
    });

    testWidgets('a turn with no distance is the turn itself: the dot is at the '
        'junction', (tester) async {
      await show(tester, size);
      final g = NavHudGeometry(size.width, size.height);
      // Mirrored, as the HUD is by default.
      final bend = NavBend.right;
      final junction = g.junction(bend);
      final box = Rect.fromCenter(
        center: Offset(size.width - junction.dx, junction.dy),
        width: g.nodeRadius * 2 - g.strokeWidth * 2,
        height: g.nodeRadius * 2 - g.strokeWidth * 2,
      );

      // `Turn right onto Mission Rd`, as Maps says it in the last metres.
      await maps(
        tester,
        NavNotification(
          title: 'Turn right onto Mission Rd',
          subText: 'Arrive 9:25 PM',
          shortCriticalText: '',
          progress: 800,
          progressMax: 6605,
          template: 'android.app.Notification\$ProgressStyle',
          arrow: _real('e687a80d8d'),
        ),
      );
      final turnNow = await pixels(tester);

      // `Head north`: no distance, and no turn in it either.
      await maps(
        tester,
        NavNotification(
          title: 'Head north',
          subText: 'Arrive 9:25 PM',
          shortCriticalText: '',
          progress: 800,
          progressMax: 6605,
          template: 'android.app.Notification\$ProgressStyle',
          arrow: _real('5c317d6e0e'),
        ),
      );
      final headNorth = await pixels(tester);

      // The hole of the ring is empty without a dot, and filled with it.
      expect(litIn(headNorth, size, box), lessThan(10));
      expect(litIn(turnNow, size, box), greaterThan(100));
    });

    testWidgets('the dot climbs as the turn comes near', (tester) async {
      await show(tester, size);
      final g = NavHudGeometry(size.width, size.height);
      final x = size.width - g.lineX;
      final nearTop = Rect.fromCenter(
        center: Offset(x, g.lineTop + 10),
        width: 40,
        height: 20,
      );
      final foot = Rect.fromCenter(
        center: Offset(x, g.lineBottom - 10),
        width: 40,
        height: 20,
      );

      await maps(tester, _turn(distance: '650 m'));
      final far = await pixels(tester);
      await maps(tester, _turn(distance: '50 m', progress: 800));
      final near = await pixels(tester);

      expect(litIn(far, size, foot), greaterThan(litIn(near, size, foot)));
      expect(
        litIn(near, size, nearTop),
        greaterThan(litIn(far, size, nearTop)),
      );
    });
  });

  group('when Maps has gone quiet', () {
    const size = Size(720, 360);

    testWidgets('the turn and the figures go, and it says why', (tester) async {
      await show(tester, size);
      await maps(tester, _turn());
      final g = NavHudGeometry(size.width, size.height);
      final bottom = Rect.fromLTWH(0, g.figuresY - 30, size.width, 60);
      final live = await pixels(tester);
      expect(litIn(live, size, bottom), greaterThan(300));

      // Twenty seconds on the move, and Maps says nothing.
      run(const Duration(seconds: 20));
      await tester.pump();
      final quiet = await pixels(tester);

      expect(nav.status.value, NavLinkStatus.stale);
      expect(
        find.byType(NavHud),
        findsOneWidget,
        reason: 'it says so, on the HUD',
      );
      expect(
        litIn(quiet, size, bottom),
        0,
        reason: 'no figure is shown as live',
      );
      // The words NO UPDATE and a dash: lit, and not the arrow.
      final right = Rect.fromLTRB(
        size.width - g.contentRight,
        g.arrow.top,
        size.width - g.arrow.left,
        g.instructionTop + 40,
      );
      expect(litIn(quiet, size, right), greaterThan(200));
      expect(litIn(quiet, size, right), lessThan(litIn(live, size, right)));
    });

    testWidgets('and is live again when Maps speaks', (tester) async {
      await show(tester, size);
      await maps(tester, _turn());
      run(const Duration(seconds: 20));
      await tester.pump();
      expect(nav.status.value, NavLinkStatus.stale);

      await maps(tester, _turn(distance: '300 m', progress: 400));

      expect(nav.status.value, NavLinkStatus.guiding);
    });
  });

  group('the geometry keeps to the HUD\'s rules (DESIGN.md 8)', () {
    for (final size in const [Size(640, 360), Size(720, 360), Size(800, 360)]) {
      test('at ${size.width.toInt()}x360', () {
        final g = NavHudGeometry(size.width, size.height);
        final h = size.height;

        // Labels and text at least 0.06H; strokes at least 5 lp.
        expect(g.labelSize, greaterThanOrEqualTo(h * 0.06 - 1e-9));
        expect(g.instructionSize, greaterThanOrEqualTo(h * 0.06));
        expect(g.strokeWidth, greaterThanOrEqualTo(TapeStroke.hud));

        // Everything inside the screen, with room.
        for (final r in [g.arrow]) {
          expect(r.left, greaterThan(0));
          expect(r.right, lessThanOrEqualTo(size.width));
          expect(r.top, greaterThan(0));
        }
        expect(g.contentRight, lessThan(size.width));
        // The line, even leaning left, stays clear of the speed: three digits of
        // it, from the middle of the left half.
        final speedRight = size.width * 0.25 + h * TapeHud.navSpeedShare * 1.1;
        expect(g.lineX - g.nodeRadius - g.bendDx, greaterThan(speedRight));
        expect(g.lineBottom, lessThan(g.figuresY - g.figureSize / 2));
        expect(g.instructionTop, greaterThan(g.arrow.bottom));
        for (final c in g.figureCentres) {
          expect(c, inInclusiveRange(0, size.width));
        }

        // The right half does not run into the speed on the left.
        expect(g.arrow.left, greaterThan(size.width * 0.5));
        expect(g.distanceMaxWidth, greaterThan(size.width * 0.12));
      });
    }

    test('both bends lean the same distance, and straight leans none', () {
      final g = NavHudGeometry(720, 360);
      final left = g.junction(NavBend.left);
      final right = g.junction(NavBend.right);
      final straight = g.junction(NavBend.straight);

      expect(straight.dx, g.lineX);
      expect(left.dx, closeTo(g.lineX - g.bendDx, 1e-9));
      expect(right.dx, closeTo(g.lineX + g.bendDx, 1e-9));
      expect(left.dy, right.dy);
    });
  });
}
