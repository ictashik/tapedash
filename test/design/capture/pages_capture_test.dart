// The Debrief, Review, Coach, History, Garage and Diagnostics on trips and a fake
// adapter made by hand, for the feature pages in docs/. (review_screens_capture_test
// waits for a simulated drive to end into the Debrief, which it no longer does.)
// Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/fuel/fuel_estimator.dart' show FuelSource;
import 'package:tapedash/money/spend_bucket.dart';
import 'package:tapedash/obd/diagnostics_source.dart';
import 'package:tapedash/obd/dtc/dtc.dart';
import 'package:tapedash/obd/dtc/dtc_descriptions.dart';
import 'package:tapedash/trips/trip.dart';
import 'package:tapedash/trips/trip_library.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/pages/coach/coach_page.dart';
import 'package:tapedash/ui/pages/diagnostics/diagnostics_page.dart';
import 'package:tapedash/ui/pages/garage/garage_page.dart';
import 'package:tapedash/ui/pages/history/history_page.dart';
import 'package:tapedash/ui/pages/review/review_page.dart';
import 'package:tapedash/ui/pages/strip/the_strip.dart';
import 'package:tapedash/vehicle/reading.dart';
import 'package:tapedash/vehicle/vehicle_state.dart' show DrivingMode;

import '../../support/sim_shell.dart';
import '../support/harness.dart';
import 'review_replay_capture_test.dart' show cityDrive;

const _size = Size(720, 360);

/// A 20:9 phone, which is wider than the others.
const _wide = Size(800, 360);

/// A trip along a wiggly route. [idleShare] of the engine time is spent standing,
/// and [gentle] picks smooth driving at about 45 km/h over a lively 55.
Future<Trip> _addTrip(
  MemoryTripRepository repo, {
  required DateTime at,
  required int minutes,
  double idleShare = 0.1,
  double hard = 0,
  double kmh = 38,
  double lat = 12.97,
}) async {
  final seconds = minutes * 60;
  final samples = <TripSample>[];
  var distance = 0.0;
  var litres = 0.0;
  var idle = 0.0;
  var normal = 0.0, idling = 0.0, hardLitres = 0.0;
  for (var t = 0; t < seconds; t++) {
    final standing = (t % 300) < 300 * idleShare;
    final v = standing ? 0.0 : kmh + 8 * math.sin(t / 40);
    final accel = !standing && hard > 0 && (t % 180) < 6;
    final lph = standing ? 0.8 : 0.9 + v * 0.045 + (accel ? 3.5 * hard : 0);
    distance += v / 3600;
    final l = lph / 3600;
    litres += l;
    if (standing) {
      idle++;
      idling += l;
    } else if (accel) {
      hardLitres += l;
    } else {
      normal += l;
    }
    samples.add(
      TripSample(
        seconds: t.toDouble(),
        speedKmh: v,
        rpm: standing ? 780 : 1500 + v * 22 + (accel ? 900 : 0),
        throttle: standing ? 0 : 14 + v * 0.18 + (accel ? 30 : 0),
        litresPerHour: lph,
        latitude: lat + distance * 0.009 * 0.7 + 0.0004 * math.sin(t / 55),
        longitude: 77.59 + distance * 0.009 * 0.7 + 0.0006 * math.cos(t / 70),
        load: 20 + v * 0.4,
        coolantC: math.min(90, 60 + t * 0.05),
        voltage: 14.0,
      ),
    );
  }
  final trip = await repo.create(
    Trip(
      startedAt: at,
      endedAt: at.add(Duration(minutes: minutes)),
      distanceKm: distance,
      litres: litres,
      cost: litres * 115,
      pricePerLitre: 115,
      idleSeconds: idle,
      engineSeconds: seconds.toDouble(),
      bucketLitres: {
        SpendBucket.normal: normal,
        SpendBucket.idling: idling,
        SpendBucket.hardAcceleration: hardLitres,
        SpendBucket.highSpeed: 0,
      },
    ),
  );
  await repo.addSamples(trip.id!, samples);
  return trip;
}

/// Steady driving at several speeds with a fuel use that is best near 55 km/h.
Future<void> _addSteady(MemoryTripRepository repo, DateTime at) async {
  final trip = await repo.create(
    Trip(
      startedAt: at,
      endedAt: at.add(const Duration(hours: 1)),
      distanceKm: 42,
      litres: 3.1,
      cost: 3.1 * 115,
      pricePerLitre: 115,
    ),
  );
  var t = 0.0;
  final samples = <TripSample>[];
  for (final kmh in const [25.0, 35.0, 45.0, 55.0, 65.0, 75.0, 85.0, 95.0]) {
    // litres an hour for a steady speed: a bowl, lowest near 55
    final lph = 0.8 + kmh * 0.03 + math.pow((kmh - 55) / 40, 2) * 2.2;
    for (var i = 0; i < 480; i++) {
      samples.add(
        TripSample(
          seconds: t++,
          speedKmh: kmh,
          rpm: 1200 + kmh * 18,
          throttle: 16 + kmh * 0.12,
          litresPerHour: lph,
        ),
      );
    }
  }
  await repo.addSamples(trip.id!, samples);
}

class _Diagnostics implements DiagnosticsSource {
  final ObservableValue<AdapterInfo?> info = ObservableValue(
    AdapterInfo(
      banner: 'ELM327 v1.5',
      protocolNumber: '6',
      supportedPids: {0x04, 0x05, 0x0B, 0x0C, 0x0D, 0x0F, 0x11, 0x2F, 0x42},
      ecuCount: 1,
      retries: 0,
      warnings: const [],
    ),
  );
  final ObservableValue<double> rate = ObservableValue(6.8);
  final ObservableValue<FuelSource> fuel = ObservableValue(
    FuelSource.speedDensity,
  );
  final ObservableValue<Reading?> volts = ObservableValue(null);

  DtcReadResult result = const DtcReadResult(
    stored: [Dtc('P0420')],
    pending: [Dtc('P0171')],
  );

  @override
  Observable<AdapterInfo?> get adapterInfo => info;
  @override
  Observable<double> get pollRate => rate;
  @override
  Observable<FuelSource> get fuelSource => fuel;
  @override
  Observable<Reading?> get voltage => volts;

  @override
  void readCodes(void Function(DtcReadResult result) done) => done(result);

  @override
  void clearCodes(void Function(DtcClearOutcome outcome) done) {
    result = const DtcReadResult();
    done(DtcClearOutcome.cleared);
  }
}

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;
  late MemoryTripRepository repo;
  late TripLibrary library;
  late ValueNotifier<DrivingMode> mode;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock(start: DateTime(2026, 3, 12, 12));
    repo = MemoryTripRepository();
    library = TripLibrary(repo);
    mode = ValueNotifier(DrivingMode.parked);
  });

  tearDown(() {
    kit.dispose();
    motion.dispose();
    mode.dispose();
  });

  Future<void> show(WidgetTester tester, Widget page) async {
    setWindow(tester, _size);
    await tester.pumpWidget(tapeHarness(kit: kit, motion: motion, child: page));
    await tester.pump();
    await tester.pump();
  }

  Future<void> run(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 50) {
      motion.advance(const Duration(milliseconds: 50), step: 0.05);
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> seedWeek(WidgetTester tester) => tester.runAsync(() async {
    await _addSteady(repo, DateTime(2026, 3, 4, 8));
    await _addTrip(
      repo,
      at: DateTime(2026, 3, 5, 9),
      minutes: 22,
      idleShare: 0.1,
    );
    await _addTrip(
      repo,
      at: DateTime(2026, 3, 6, 18, 10),
      minutes: 31,
      idleShare: 0.35,
      kmh: 24,
    );
    await _addTrip(
      repo,
      at: DateTime(2026, 3, 9, 8, 40),
      minutes: 26,
      idleShare: 0.08,
      hard: 1,
      kmh: 44,
    );
    await _addTrip(
      repo,
      at: DateTime(2026, 3, 10, 9, 5),
      minutes: 24,
      idleShare: 0.12,
      kmh: 40,
    );
    await _addTrip(
      repo,
      at: DateTime(2026, 3, 11, 19),
      minutes: 38,
      idleShare: 0.28,
      kmh: 28,
    );
    // The weeks before, one short trip each, so that the trend has a line.
    for (var w = 1; w <= 7; w++) {
      await _addTrip(
        repo,
        at: DateTime(2026, 3, 10 - 7 * w, 9),
        minutes: 9,
        idleShare: 0.1 + 0.03 * (w % 3),
        kmh: 34 + 3.0 * (w % 4),
        lat: 12.95 + w * 0.001,
      );
    }
    // The latest, a drive round the block with two stops at signals.
    final city = cityDrive();
    final latest = await repo.create(
      Trip(
        startedAt: DateTime(2026, 3, 12, 8, 30),
        endedAt: DateTime(2026, 3, 12, 8, 37),
        distanceKm: 2.5,
        litres: 0.22,
        cost: 25.3,
        pricePerLitre: 115,
        idleSeconds: 28,
        engineSeconds: city.length.toDouble(),
        bucketLitres: {
          SpendBucket.normal: 0.17,
          SpendBucket.idling: 0.02,
          SpendBucket.hardAcceleration: 0.03,
          SpendBucket.highSpeed: 0,
        },
      ),
    );
    await repo.addSamples(latest.id!, city);
    await library.refresh();
  });

  testWidgets('the Debrief and Review', (tester) async {
    await seedWeek(tester);
    final request = DebriefRequest();
    addTearDown(request.dispose);
    await show(
      tester,
      ReviewPage(
        library: library,
        mode: mode,
        width: _size.width,
        height: _size.height,
        debrief: request,
      ),
    );
    await run(tester, 800);
    tester.state<ReviewPageState>(find.byType(ReviewPage)).playDebrief();
    await tester.pump();
    await run(tester, 1400);
    await capturePng(tester, 'page-debrief-1');
    await run(tester, 1600);
    await capturePng(tester, 'page-debrief-2');
    await run(tester, 1500);
    await capturePng(tester, 'page-debrief-3');
    await run(tester, 6000);
    await capturePng(tester, 'page-review');
  }, skip: !enabled);

  testWidgets('Coach', (tester) async {
    await seedWeek(tester);
    await show(
      tester,
      CoachPage(
        library: library,
        clock: clock,
        mode: mode,
        width: _size.width,
        height: _size.height,
      ),
    );
    await run(tester, 3000);
    await capturePng(tester, 'page-coach');
  }, skip: !enabled);

  testWidgets('History', (tester) async {
    await seedWeek(tester);
    await show(
      tester,
      HistoryPage(
        library: library,
        clock: clock,
        width: _size.width,
        height: _size.height,
      ),
    );
    await run(tester, 2500);
    await capturePng(tester, 'page-history');
  }, skip: !enabled);

  testWidgets('Garage', (tester) async {
    final app = await AppServices.memory();
    await show(
      tester,
      GaragePage(
        settings: app.settings,
        services: app,
        library: library,
        mode: mode,
        width: _size.width,
        height: _size.height,
        onClose: () {},
        onSetPrice: () {},
        onChangeAdapter: () {},
        version: '1.0',
      ),
    );
    await run(tester, 1500);
    await capturePng(tester, 'page-garage-1');
    for (var i = 2; i <= 4; i++) {
      await tester.drag(find.byType(GaragePage), const Offset(0, -300));
      await run(tester, 900);
      await capturePng(tester, 'page-garage-$i');
    }
  }, skip: !enabled);

  testWidgets('Diagnostics', (tester) async {
    final descriptions = DtcDescriptions.parse(
      '{"P0420":"Catalytic converter working below its threshold (bank 1)",'
      '"P0171":"Mixture too lean (bank 1)"}',
    );
    await show(
      tester,
      DiagnosticsPage(
        source: _Diagnostics(),
        mode: mode,
        width: _size.width,
        height: _size.height,
        onClose: () {},
        descriptions: descriptions,
      ),
    );
    await run(tester, 1500);
    await capturePng(tester, 'page-diagnostics');
  }, skip: !enabled);

  testWidgets('Money, in a simulated city drive', (tester) async {
    setWindow(tester, _wide);
    final simClock = FakeClock()..advance(const Duration(seconds: 100));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: SimDriveShell(
          clock: simClock,
          scheduler: simClock,
          scenario: 'city_stop_go',
        ),
      ),
    );
    Future<void> sim(int ms) async {
      for (var t = 0; t < ms; t += 50) {
        motion.tick(0.05);
        simClock.advance(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    tester.state<TheStripState>(find.byType(TheStrip)).goTo(TheStrip.moneyPage);
    // Moving between two signals.
    await sim(615000);
    await capturePng(tester, 'page-money-motion');
  }, skip: !enabled);
}
