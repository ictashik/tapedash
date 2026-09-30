// Review, the Debrief, Coach and History (DESIGN.md 7.5 to 7.7), on a trip log
// filled by hand: each lays out at the three phone sizes, tips never show while
// the car moves, demo trips stay out of the statistics, and the Debrief plays,
// skips and is put away.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/money/spend_bucket.dart';
import 'package:tapedash/trips/trip.dart';
import 'package:tapedash/trips/trip_library.dart';
import 'package:tapedash/ui/design/components/controls/tape_scroll_segmented.dart';
import 'package:tapedash/ui/design/components/controls/tape_square_button.dart';
import 'package:tapedash/ui/design/components/route_trail.dart';
import 'package:tapedash/ui/design/components/route_zoom_buttons.dart';
import 'package:tapedash/ui/design/components/telemetry_scrubber.dart';
import 'package:tapedash/ui/design/components/trip_transport.dart';
import 'package:tapedash/ui/design/icons/icons.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/pages/coach/coach_page.dart';
import 'package:tapedash/ui/pages/history/history_page.dart';
import 'package:tapedash/ui/pages/review/replay_hud.dart';
import 'package:tapedash/ui/pages/review/review_page.dart';
import 'package:tapedash/vehicle/vehicle_state.dart' show DrivingMode;

import '../design/support/harness.dart';

const _sizes = [Size(640, 360), Size(720, 360), Size(800, 360)];

/// A trip with a tip in it: 14 minutes of idling in a 20 minute trip.
Future<Trip> addTrip(
  MemoryTripRepository repo, {
  DateTime? at,
  bool demo = false,
  bool gps = true,
  double idling = 0.24,
  bool channels = false,
}) async {
  final trip = await repo.create(
    Trip(
      startedAt: at ?? DateTime(2026, 3, 10, 9),
      endedAt: (at ?? DateTime(2026, 3, 10, 9)).add(
        const Duration(minutes: 20),
      ),
      isDemo: demo,
      distanceKm: 8.2,
      litres: 0.9 + idling,
      cost: (0.9 + idling) * 100,
      pricePerLitre: 100,
      idleSeconds: 14 * 60,
      engineSeconds: 20 * 60,
      bucketLitres: {
        SpendBucket.normal: 0.9,
        SpendBucket.idling: idling,
        SpendBucket.hardAcceleration: 0,
        SpendBucket.highSpeed: 0,
      },
    ),
  );
  await repo.addSamples(trip.id!, [
    for (var t = 0; t < 120; t++)
      TripSample(
        seconds: t.toDouble(),
        speedKmh: 20 + 20 * ((t % 40) / 40),
        rpm: 1800,
        throttle: 20,
        litresPerHour: 3,
        latitude: gps ? 12.9 + t * 0.0001 : null,
        longitude: gps ? 77.6 + (t % 20) * 0.00005 : null,
        load: channels ? 30 + 20 * ((t % 30) / 30) : null,
        coolantC: channels ? 70 + t * 0.2 : null,
        voltage: channels ? 13.8 + 0.4 * ((t % 10) / 10) : null,
      ),
  ]);
  return trip;
}

/// Steady driving in three speed bands, enough for a sweet spot at 50 to 60.
Future<void> addSteadyTrip(MemoryTripRepository repo) async {
  final trip = await repo.create(
    Trip(
      startedAt: DateTime(2026, 3, 9, 9),
      endedAt: DateTime(2026, 3, 9, 10),
      distanceKm: 40,
      litres: 3,
      cost: 300,
      pricePerLitre: 100,
    ),
  );
  var t = 0.0;
  final samples = <TripSample>[];
  for (final (kmh, lph, seconds) in const [
    (35.0, 5.0, 450),
    (55.0, 3.0, 300),
    (85.0, 5.5, 200),
  ]) {
    for (var i = 0; i < seconds; i++) {
      samples.add(
        TripSample(
          seconds: t++,
          speedKmh: kmh,
          rpm: 2000,
          throttle: 20,
          litresPerHour: lph,
        ),
      );
    }
  }
  await repo.addSamples(trip.id!, samples);
}

void main() {
  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;
  late MemoryTripRepository repo;
  late TripLibrary library;
  late ValueNotifier<DrivingMode> mode;

  setUpAll(loadTapeFonts);

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock(start: DateTime(2026, 3, 10, 12));
    repo = MemoryTripRepository();
    library = TripLibrary(repo);
    mode = ValueNotifier(DrivingMode.parked);
  });

  tearDown(() {
    kit.dispose();
    motion.dispose();
    mode.dispose();
  });

  Future<void> show(
    WidgetTester tester,
    Widget Function(Size size) page, {
    Size size = const Size(720, 360),
  }) async {
    setWindow(tester, size);
    await tester.pumpWidget(
      tapeHarness(kit: kit, motion: motion, child: page(size)),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester, [int ms = 1000]) async {
    for (var t = 0; t < ms; t += 100) {
      motion.advance(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('Review', () {
    ReviewPage review(Size s, {DebriefRequest? debrief}) => ReviewPage(
      library: library,
      mode: mode,
      width: s.width,
      height: s.height,
      debrief: debrief,
    );

    for (final size in _sizes) {
      testWidgets('lays out at ${size.width.toInt()}x360', (tester) async {
        await tester.runAsync(() async {
          await addTrip(repo);
          await library.refresh();
        });
        await show(tester, review, size: size);
        expect(find.byType(TipPanel), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('with no trips it says so', (tester) async {
      await show(tester, review);
      expect(find.textContaining('No trips yet'), findsOneWidget);
    });

    testWidgets(
      'a trip with no GPS says there is no route, and still lays out',
      (tester) async {
        await tester.runAsync(() async {
          await addTrip(repo, gps: false);
          await library.refresh();
        });
        await show(tester, review);
        expect(find.textContaining('no GPS'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('tips never appear while the vehicle is moving', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await addTrip(repo);
        await library.refresh();
      });
      await show(tester, review);
      expect(find.byType(TipPanel), findsOneWidget);
      expect(find.textContaining('went on idling'), findsOneWidget);

      mode.value = DrivingMode.motion;
      await tester.pump();
      expect(find.byType(TipPanel), findsNothing);
      expect(find.textContaining('went on idling'), findsNothing);

      mode.value = DrivingMode.parked;
      await tester.pump();
      expect(find.byType(TipPanel), findsOneWidget);
    });

    testWidgets('the Debrief plays for 4.5 s, and a tap skips it', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await addTrip(repo);
        await library.refresh();
      });
      await show(tester, review);
      final state = tester.state<ReviewPageState>(find.byType(ReviewPage));
      expect(state.isDebriefing, isFalse);

      state.playDebrief();
      await tester.pump();
      expect(state.isDebriefing, isTrue);
      await settle(tester, 2000);
      expect(state.isDebriefing, isTrue);
      await settle(tester, 3000);
      expect(state.isDebriefing, isFalse);

      state.playDebrief();
      await tester.pump();
      expect(state.isDebriefing, isTrue);
      await tester.tapAt(const Offset(300, 150));
      await tester.pump();
      expect(state.isDebriefing, isFalse, reason: 'at the touch, not after');
      // Let the map's double-tap wait run out.
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a request for the Debrief is taken once the page is on screen', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await addTrip(repo);
        await library.refresh();
      });
      final request = DebriefRequest();
      addTearDown(request.dispose);
      // Asked for before the page is there, as the shell does when the Strip has
      // not built Review yet.
      request.request();
      await show(tester, (s) => review(s, debrief: request));
      await tester.pump();
      final state = tester.state<ReviewPageState>(find.byType(ReviewPage));
      expect(state.isDebriefing, isTrue);
      expect(request.pending, isFalse);

      // Taken: the same request does not play it again.
      await settle(tester, 5000);
      expect(state.isDebriefing, isFalse);
      await tester.pump();
      expect(state.isDebriefing, isFalse);
    });

    testWidgets('a cleared request does not play', (tester) async {
      await tester.runAsync(() async {
        await addTrip(repo);
        await library.refresh();
      });
      final request = DebriefRequest();
      addTearDown(request.dispose);
      request.request();
      request.clear();
      await show(tester, (s) => review(s, debrief: request));
      await tester.pump();
      final state = tester.state<ReviewPageState>(find.byType(ReviewPage));
      expect(state.isDebriefing, isFalse);
    });

    testWidgets('the metric selector recolours without an exception', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await addTrip(repo);
        await library.refresh();
      });
      await show(tester, review);
      await tester.tap(find.text('THROTTLE'));
      await tester.pump();
      await tester.tap(find.text('₹/KM').first);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('Review: the telemetry channels', () {
    ReviewPage review(Size s) => ReviewPage(
      library: library,
      mode: mode,
      width: s.width,
      height: s.height,
    );

    testWidgets('a trip that kept them offers all seven metrics', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await addTrip(repo, channels: true);
        await library.refresh();
      });
      await show(tester, review);

      final state = tester.state<ReviewPageState>(find.byType(ReviewPage));
      expect(state.availableMetrics, ReviewMetric.values);
      expect(
        [for (final m in ReviewMetric.values) m.label],
        ['Speed', 'RPM', 'Throttle', 'Load', 'Coolant', 'Volts', '₹/km'],
      );
    });

    testWidgets('an older trip, with none of them, offers only what it has', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await addTrip(repo);
        await library.refresh();
      });
      await show(tester, review);

      final state = tester.state<ReviewPageState>(find.byType(ReviewPage));
      expect(state.availableMetrics, [
        ReviewMetric.speed,
        ReviewMetric.rpm,
        ReviewMetric.throttle,
        ReviewMetric.costPerKm,
      ]);
    });

    for (final size in _sizes) {
      testWidgets(
        'every metric can be chosen, and lays out, at ${size.width.toInt()}x360',
        (tester) async {
          await tester.runAsync(() async {
            await addTrip(repo, channels: true);
            await library.refresh();
          });
          await show(tester, review, size: size);
          final state = tester.state<ReviewPageState>(find.byType(ReviewPage));

          for (final m in ReviewMetric.values) {
            final label = find.descendant(
              of: find.byType(TapeScrollSegmented<ReviewMetric>),
              matching: find.text(m.label.toUpperCase()),
            );
            // The selector scrolls: bring the cell into view, then tap it.
            await tester.ensureVisible(label);
            await tester.pump();
            await tester.tap(label, warnIfMissed: false);
            await settle(tester, 300);
            expect(state.metric, m, reason: m.label);
            expect(tester.takeException(), isNull, reason: m.label);
          }
        },
      );
    }

    testWidgets('a channel with a reading at the cursor says it in words', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await addTrip(repo, channels: true);
        await library.refresh();
      });
      await show(tester, review);
      final label = find.descendant(
        of: find.byType(TapeScrollSegmented<ReviewMetric>),
        matching: find.text('COOLANT'),
      );
      await tester.ensureVisible(label);
      await tester.pump();
      await tester.tap(label, warnIfMissed: false);
      await settle(tester, 300);

      final state = tester.state<ReviewPageState>(find.byType(ReviewPage));
      state.debugSetCursor(60);
      await tester.pump();

      expect(find.textContaining('°C COOLANT'), findsOneWidget);
      // 70 + 60 * 0.2 = 82.
      expect(find.text('82 °C COOLANT'), findsOneWidget);
    });
  });

  group('Review: the route map is interactive', () {
    ReviewPage review(Size s) => ReviewPage(
      library: library,
      mode: mode,
      width: s.width,
      height: s.height,
    );

    Future<ReviewPageState> open(
      WidgetTester tester, {
      Size size = const Size(720, 360),
    }) async {
      await tester.runAsync(() async {
        await addTrip(repo, channels: true);
        await library.refresh();
      });
      await show(tester, review, size: size);
      return tester.state<ReviewPageState>(find.byType(ReviewPage));
    }

    Rect panel(WidgetTester tester) => tester.getRect(find.byType(RouteTrail));

    Future<void> settleView(WidgetTester tester) => settle(tester, 1500);

    testWidgets('the route can be zoomed by pinching, about the fingers', (
      tester,
    ) async {
      final state = await open(tester);
      final p = panel(tester);
      expect(state.routeView.scale, 1);

      final a = await tester.startGesture(
        p.center + const Offset(-20, 0),
        pointer: 1,
      );
      final b = await tester.startGesture(
        p.center + const Offset(20, 0),
        pointer: 2,
      );
      await tester.pump();
      for (var i = 1; i <= 8; i++) {
        await a.moveTo(p.center + Offset(-20 - 5.0 * i, 0));
        await b.moveTo(p.center + Offset(20 + 5.0 * i, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(state.routeView.scale, inInclusiveRange(1.4, 3.1));
      await a.up();
      await b.up();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('zoomed in, a drag pans; at the whole route it does nothing', (
      tester,
    ) async {
      final state = await open(tester);
      final p = panel(tester);

      // At 1 there is nowhere to go.
      await tester.dragFrom(p.center, const Offset(-50, -30));
      await tester.pump();
      expect(state.routeView.offset, Offset.zero);

      state.routeView.zoomAt(p.center - p.topLeft, 4);
      final before = state.routeView.offset;
      await tester.dragFrom(p.center, const Offset(-40, -20));
      await tester.pump();

      expect(state.routeView.offset, isNot(before));
      expect(
        state.routeView.scale,
        closeTo(4, 1e-9),
        reason: 'a drag is not a zoom',
      );
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a double-tap zooms in, and again when well in goes back out', (
      tester,
    ) async {
      final state = await open(tester);
      final p = panel(tester);

      Future<void> doubleTap() async {
        await tester.tapAt(p.center);
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tapAt(p.center);
        await tester.pump();
        await settleView(tester);
      }

      await doubleTap();
      expect(state.routeView.scale, closeTo(2.5, 0.05));
      await doubleTap();
      expect(state.routeView.scale, closeTo(6.25, 0.1));
      await doubleTap();
      expect(state.routeView.scale, closeTo(1, 0.05));
    });

    testWidgets('a tap on the route puts the scrubber cursor on that point', (
      tester,
    ) async {
      final state = await open(tester);
      final g = state.routeGeometry!;
      final p = panel(tester);
      expect(state.cursorSample, isNull);

      final k = g.length ~/ 2;
      await tester.tapAt(p.topLeft + Offset(g.xs[k], g.ys[k]));
      await tester.pump(const Duration(milliseconds: 400));

      expect(state.cursorSample, g.sampleIndex[k]);
    });

    testWidgets('a tap far from the route picks nothing', (tester) async {
      final state = await open(tester);
      final p = panel(tester);

      // The far corner of the panel, away from a route that runs up its middle.
      await tester.tapAt(p.bottomRight - const Offset(4, 4));
      await tester.pump(const Duration(milliseconds: 400));

      expect(state.cursorSample, isNull);
    });

    testWidgets('a tap on the route while zoomed picks through the zoom', (
      tester,
    ) async {
      final state = await open(tester);
      final g = state.routeGeometry!;
      final p = panel(tester);
      final k = g.length ~/ 3;
      state.routeView.zoomAt(Offset(g.xs[k], g.ys[k]), 6);
      await tester.pump();

      final onScreen = state.routeView.toScreen(Offset(g.xs[k], g.ys[k]));
      await tester.tapAt(p.topLeft + onScreen);
      await tester.pump(const Duration(milliseconds: 400));

      expect(state.cursorSample, g.sampleIndex[k]);
    });

    testWidgets('the buttons zoom in, out and back to the whole route', (
      tester,
    ) async {
      final state = await open(tester);
      Finder button(TapeIcon icon) =>
          find.byWidgetPredicate((w) => w is TapeIconView && w.icon == icon);

      await tester.tap(button(TapeIcon.zoomIn));
      await settleView(tester);
      expect(state.routeView.scale, closeTo(2, 0.02));

      await tester.tap(button(TapeIcon.zoomIn));
      await settleView(tester);
      expect(state.routeView.scale, closeTo(4, 0.05));

      await tester.tap(button(TapeIcon.zoomOut));
      await settleView(tester);
      expect(state.routeView.scale, closeTo(2, 0.02));

      await tester.tap(button(TapeIcon.fit));
      await settleView(tester);
      expect(state.routeView.scale, closeTo(1, 0.02));
      expect(tester.takeException(), isNull);
    });

    testWidgets('zooming out and fit do nothing at the whole route', (
      tester,
    ) async {
      final state = await open(tester);

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is TapeIconView && w.icon == TapeIcon.zoomOut,
        ),
      );
      await settleView(tester);

      expect(state.routeView.scale, 1);
    });

    testWidgets(
      'moving the scrubber to somewhere off the zoomed view brings the view to it',
      (tester) async {
        final state = await open(tester);
        final g = state.routeGeometry!;
        state.routeView.zoomAt(Offset.zero, 8);
        await tester.pump();

        // The end of the route is far from the top-left corner the view is on.
        state.debugSetCursor(g.sampleIndex.last);
        await settleView(tester);

        final end = state.routeView.toScreen(Offset(g.xs.last, g.ys.last));
        final size = panel(tester).size;
        expect(end.dx, inInclusiveRange(0, size.width));
        expect(end.dy, inInclusiveRange(0, size.height));
      },
    );

    testWidgets('choosing another trip goes back to the whole route', (
      tester,
    ) async {
      final state = await open(tester);
      state.routeView.zoomAt(const Offset(50, 50), 5);
      await tester.runAsync(() async {
        final other = await addTrip(repo, at: DateTime(2026, 3, 11, 9));
        await library.refresh();
        library.select(other);
      });
      await tester.pump();
      await tester.pump();

      expect(state.routeView.scale, 1);
    });

    for (final size in _sizes) {
      testWidgets('lays out, zoomed and panned, at ${size.width.toInt()}x360', (
        tester,
      ) async {
        final state = await open(tester, size: size);
        final p = panel(tester);
        state.routeView.zoomAt(p.center - p.topLeft, 10);
        await tester.dragFrom(p.center, const Offset(30, 20));
        await settleView(tester);

        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Coach', () {
    CoachPage coach(Size s) => CoachPage(
      library: library,
      clock: clock,
      mode: mode,
      width: s.width,
      height: s.height,
    );

    for (final size in _sizes) {
      testWidgets('lays out at ${size.width.toInt()}x360', (tester) async {
        await tester.runAsync(() async {
          await addSteadyTrip(repo);
          await addTrip(repo);
          await library.refresh();
        });
        await show(tester, coach, size: size);
        await settle(tester, 1500);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('with no steady driving it says what fills the curve in', (
      tester,
    ) async {
      await show(tester, coach);
      await settle(tester, 1500);
      expect(find.text('Not enough steady driving yet.'), findsOneWidget);
      expect(find.textContaining('curve fills in'), findsOneWidget);
    });

    testWidgets('the sweet spot is named from real trips', (tester) async {
      await tester.runAsync(() async {
        await addSteadyTrip(repo);
        await library.refresh();
      });
      await show(tester, coach);
      await settle(tester, 1500);
      expect(find.text('50–60 km/h'), findsOneWidget);
    });

    testWidgets('demo trips do not count: no sweet spot, and ₹0 this week', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await addTrip(repo, demo: true, at: DateTime(2026, 3, 10, 8));
        await library.refresh();
      });
      await show(tester, coach);
      await settle(tester, 1500);
      expect(find.text('Not enough steady driving yet.'), findsOneWidget);
      expect(find.text('₹0'), findsWidgets);
      // Its tip is not among the recent tips either.
      expect(find.textContaining('went on idling'), findsNothing);
    });

    testWidgets('recent tips show while parked and never while moving', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await addTrip(repo);
        await library.refresh();
      });
      await show(tester, coach);
      await settle(tester, 1500);
      expect(find.textContaining('went on idling'), findsOneWidget);

      mode.value = DrivingMode.motion;
      await tester.pump();
      expect(find.textContaining('went on idling'), findsNothing);
    });
  });

  group('History', () {
    HistoryPage history(Size s, {ValueChanged<Trip>? onOpen}) => HistoryPage(
      library: library,
      clock: clock,
      width: s.width,
      height: s.height,
      onOpen: onOpen,
    );

    for (final size in _sizes) {
      testWidgets('lays out at ${size.width.toInt()}x360', (tester) async {
        await tester.runAsync(() async {
          await addTrip(repo);
          await addTrip(repo, at: DateTime(2026, 3, 8, 18), gps: false);
          await library.refresh();
        });
        await show(tester, history, size: size);
        expect(find.byType(TripRow), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('an empty log says so', (tester) async {
      await show(tester, history);
      expect(find.textContaining('No trips'), findsOneWidget);
    });

    testWidgets('a demo trip is listed with its badge but not counted', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await addTrip(repo, demo: true);
        await library.refresh();
      });
      await show(tester, history);
      expect(find.byType(TripRow), findsOneWidget);
      expect(find.text('DEMO'), findsOneWidget);
      // The month's header counts only real trips.
      expect(find.text('0.0 km'), findsOneWidget);
    });

    testWidgets('tapping a row selects that trip and opens it', (tester) async {
      Trip? opened;
      await tester.runAsync(() async {
        await addTrip(repo, at: DateTime(2026, 3, 8, 18));
        await addTrip(repo);
        await library.refresh();
      });
      await show(tester, (s) => history(s, onOpen: (t) => opened = t));
      final older = library.trips.value.last;
      expect(library.selected.value, isNot(older));
      await tester.tap(find.byType(TripRow).last);
      await tester.pump();
      expect(library.selected.value?.id, older.id);
      expect(opened?.id, older.id);
    });
  });

  group('Review: the replay of a trip', () {
    ReviewPage review(Size s, {DebriefRequest? debrief}) => ReviewPage(
      library: library,
      mode: mode,
      width: s.width,
      height: s.height,
      debrief: debrief,
    );

    Future<ReviewPageState> open(
      WidgetTester tester, {
      Size size = const Size(720, 360),
      bool gps = true,
    }) async {
      await tester.runAsync(() async {
        await addTrip(repo, channels: true, gps: gps);
        await library.refresh();
      });
      await show(tester, review, size: size);
      return tester.state<ReviewPageState>(find.byType(ReviewPage));
    }

    Finder transport() => find.descendant(
      of: find.byType(TripTransport),
      matching: find.byType(TapeSquareButton),
    );

    Future<void> tapPlay(WidgetTester tester) async {
      await tester.tap(transport().at(0));
      await tester.pump();
    }

    /// Runs [seconds] of the replay at frame rate.
    Future<void> run(WidgetTester tester, double seconds) async {
      for (var t = 0.0; t < seconds; t += 0.1) {
        motion.advance(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('a trip has a play button, a speed and a stop that waits', (
      tester,
    ) async {
      final state = await open(tester);

      expect(transport(), findsNWidgets(3));
      expect(find.text('1×'), findsOneWidget);
      expect(state.isReplaying, isFalse);
      expect(state.player, isNotNull);
      expect(find.byType(ReplayHud), findsNothing);
      // Each is a 48 lp touch target.
      for (var i = 0; i < 3; i++) {
        expect(tester.getSize(transport().at(i)), const Size(48, 48));
      }
    });

    testWidgets('play brings up the instruments and the car, and follows it', (
      tester,
    ) async {
      final state = await open(tester);

      await tapPlay(tester);
      await run(tester, 3);

      expect(state.isReplaying, isTrue);
      expect(state.player!.isPlaying, isTrue);
      expect(find.byType(ReplayHud), findsOneWidget);
      expect(state.car.visible, isTrue);
      expect(state.routeView.isChasing, isTrue);
      expect(state.routeView.scale, greaterThan(2));
      // Heading up, the car is on the panel's middle line, below its middle (the
      // road ahead has the room).
      final panel = tester.getSize(find.byType(RouteTrail));
      final at = state.routeView.toScreen(Offset(state.car.x, state.car.y));
      expect(at.dx, closeTo(panel.width / 2, 0.5));
      expect(at.dy, greaterThan(panel.height / 2));
      expect(at.dy, lessThan(panel.height));
    });

    testWidgets('a replay gives the map the tip\'s room', (tester) async {
      final state = await open(tester);
      final before = tester.getSize(find.byType(RouteTrail)).height;
      expect(find.byType(TipPanel), findsOneWidget);

      await tapPlay(tester);
      await run(tester, 1);

      expect(
        tester.getSize(find.byType(RouteTrail)).height,
        greaterThan(before),
      );
      expect(find.byType(TipPanel), findsNothing);

      state.endReplay();
      await run(tester, 1);
      expect(tester.getSize(find.byType(RouteTrail)).height, before);
      expect(find.byType(TipPanel), findsOneWidget);
    });

    testWidgets(
      'the play head, the scrubber\'s cursor and the car move with it',
      (tester) async {
        final state = await open(tester);

        await tapPlay(tester);
        await run(tester, 5);

        expect(state.player!.seconds, closeTo(5, 0.3));
        expect(state.cursorSample, closeTo(5, 1));
        final first = state.car.point;
        await run(tester, 5);
        expect(state.car.point, greaterThan(first));
      },
    );

    testWidgets('the speed button goes 2x, 3x, and round to 1x', (
      tester,
    ) async {
      final state = await open(tester);

      await tester.tap(transport().at(1));
      await tester.pump();
      expect(find.text('2×'), findsOneWidget);
      await tester.tap(transport().at(1));
      await tester.pump();
      expect(find.text('3×'), findsOneWidget);

      await tapPlay(tester);
      await run(tester, 4);
      expect(state.player!.seconds, closeTo(12, 0.8));

      await tester.tap(transport().at(1));
      await tester.pump();
      expect(find.text('1×'), findsOneWidget);
    });

    testWidgets('pause holds the moment, and play carries on', (tester) async {
      final state = await open(tester);

      await tapPlay(tester);
      await run(tester, 3);
      await tapPlay(tester);
      final held = state.player!.seconds;
      await run(tester, 3);

      expect(state.player!.isPlaying, isFalse);
      expect(state.player!.seconds, held);
      expect(state.isReplaying, isTrue, reason: 'paused is still a replay');

      await tapPlay(tester);
      await run(tester, 2);
      expect(state.player!.seconds, greaterThan(held + 1));
    });

    testWidgets('stop leaves the replay: the receipt is back, the map whole', (
      tester,
    ) async {
      final state = await open(tester);
      await tapPlay(tester);
      await run(tester, 4);
      final where = state.cursorSample;

      await tester.tap(transport().at(2));
      await tester.pump();
      await run(tester, 2);

      expect(state.isReplaying, isFalse);
      expect(state.player!.isPlaying, isFalse);
      expect(state.car.visible, isFalse);
      expect(find.byType(ReplayHud), findsNothing);
      expect(state.routeView.isChasing, isFalse);
      expect(state.routeView.scale, closeTo(1, 0.02));
      expect(state.cursorSample, where, reason: 'the cursor stays');
    });

    testWidgets('dragging the scrubber while it plays moves the play head', (
      tester,
    ) async {
      final state = await open(tester);
      await tapPlay(tester);
      await run(tester, 1);

      final scrubber = tester.getRect(find.byType(TelemetryScrubber));
      await tester.tapAt(
        Offset(scrubber.left + scrubber.width * 0.75, scrubber.center.dy),
      );
      // A tap waits out the double-tap before it is one.
      await tester.pump(const Duration(milliseconds: 400));

      expect(state.player!.seconds, closeTo(119 * 0.75, 1.5));
      expect(state.player!.isPlaying, isTrue);
    });

    testWidgets('a tap on the map while it plays takes the car there', (
      tester,
    ) async {
      final state = await open(tester);
      await tapPlay(tester);
      await run(tester, 1);
      // Out of the chase, to see the whole route and pick a point on it.
      await tester.tap(find.byType(TapeSquareButton).first);
      await tester.pump();
      state.routeView.reset();
      await run(tester, 1);

      final g = state.routeGeometry!;
      final panel = tester.getRect(find.byType(RouteTrail));
      final k = g.length * 3 ~/ 4;
      final p = state.routeView.toScreen(Offset(g.xs[k], g.ys[k]));
      await tester.tapAt(panel.topLeft + p);
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        state.player!.playback.sampleAt(state.player!.seconds),
        closeTo(g.sampleIndex[k], 2.5),
      );
    });

    testWidgets('a drag on the map lets go of the car; FOLLOW takes it back', (
      tester,
    ) async {
      final state = await open(tester);
      await tapPlay(tester);
      await run(tester, 2);
      expect(state.isFollowing, isTrue);

      final panel = tester.getRect(find.byType(RouteTrail));
      await tester.dragFrom(panel.center, const Offset(40, 10));
      await run(tester, 2);

      expect(state.isFollowing, isFalse);
      expect(state.routeView.isChasing, isFalse);
      expect(state.routeView.rotation, closeTo(0, 0.01), reason: 'north up');

      // FOLLOW is the crosshair, first among the map's buttons while replaying.
      final follow = find.descendant(
        of: find.byType(RouteZoomButtons),
        matching: find.byType(TapeSquareButton),
      );
      await tester.tap(follow.first);
      await run(tester, 2);

      expect(state.isFollowing, isTrue);
      expect(state.routeView.isChasing, isTrue);
    });

    testWidgets('the map turns with the car, and N keeps it north up', (
      tester,
    ) async {
      final state = await open(tester);
      await tapPlay(tester);
      await run(tester, 4);
      expect(state.isHeadingUp, isTrue);
      expect(state.routeView.rotation.abs(), greaterThan(0.01));

      final buttons = find.descendant(
        of: find.byType(RouteZoomButtons),
        matching: find.byType(TapeSquareButton),
      );
      // The turn button comes before FOLLOW while following.
      await tester.tap(buttons.first);
      await tester.pump();
      await run(tester, 4);

      expect(state.isHeadingUp, isFalse);
      expect(state.routeView.rotation, closeTo(0, 0.01));
    });

    testWidgets('the instruments show the moment: speed, ₹ so far, time', (
      tester,
    ) async {
      final state = await open(tester);
      await tapPlay(tester);
      await run(tester, 10);

      final f = state.player!.frame;
      expect(f.speedKmh, greaterThan(15));
      expect(f.cost, greaterThan(0));
      Finder inHud(String text) => find.descendant(
        of: find.byType(ReplayHud),
        matching: find.text(text),
      );
      expect(inHud('KM/H'), findsOneWidget);
      expect(inHud('RPM'), findsOneWidget);
      expect(inHud('SPENT'), findsOneWidget);
      expect(inHud('DISTANCE'), findsOneWidget);
      expect(inHud('TIME'), findsOneWidget);
    });

    testWidgets('a trip with no GPS still replays, without a map', (
      tester,
    ) async {
      final state = await open(tester, gps: false);

      await tapPlay(tester);
      await run(tester, 3);

      expect(state.isReplaying, isTrue);
      expect(find.byType(ReplayHud), findsOneWidget);
      expect(state.car.visible, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('choosing another trip ends the replay', (tester) async {
      await tester.runAsync(() async {
        await addTrip(repo, channels: true);
        await addTrip(repo, at: DateTime(2026, 3, 8, 18));
        await library.refresh();
      });
      await show(tester, review);
      final state = tester.state<ReviewPageState>(find.byType(ReviewPage));
      await tapPlay(tester);
      await run(tester, 2);
      expect(state.isReplaying, isTrue);

      await tester.runAsync(() async {
        library.select(library.trips.value.last);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.pump();

      expect(state.isReplaying, isFalse);
      expect(state.player!.seconds, 0);
    });

    testWidgets('the Debrief ends a replay', (tester) async {
      final request = DebriefRequest();
      await tester.runAsync(() async {
        await addTrip(repo, channels: true);
        await library.refresh();
      });
      await show(tester, (s) => review(s, debrief: request));
      final state = tester.state<ReviewPageState>(find.byType(ReviewPage));
      await tapPlay(tester);
      await run(tester, 2);

      state.playDebrief();
      await tester.pump();

      expect(state.isReplaying, isFalse);
    });

    for (final size in _sizes) {
      testWidgets('it lays out at ${size.width.toInt()}x360 while it plays', (
        tester,
      ) async {
        final state = await open(tester, size: size);
        await tapPlay(tester);
        await run(tester, 6);
        expect(tester.takeException(), isNull);

        // The instruments stay inside their column, and clear of the scrubber.
        final hud = tester.getRect(find.byType(ReplayHud));
        final scrubber = tester.getRect(find.byType(TelemetryScrubber));
        expect(hud.bottom, lessThanOrEqualTo(scrubber.top));
        expect(hud.right, lessThanOrEqualTo(size.width));
        // The transport is left of the scrubber, and does not overlap it.
        expect(
          tester.getRect(find.byType(TripTransport)).right,
          lessThanOrEqualTo(scrubber.left),
        );
        expect(state.isReplaying, isTrue);
      });
    }
  });
}
