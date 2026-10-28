// The phase 4 screens: the money signals and figure, the Money page in Motion
// and Parked, the Pit Stop page and its numpad, and the clusters' money slots at
// the three screen sizes.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/app/drive_services.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/money/pit_stop_form.dart';
import 'package:tapedash/money/spend_bucket.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/components/controls/tape_numpad.dart';
import 'package:tapedash/ui/design/components/eco_bar.dart';
import 'package:tapedash/ui/design/components/money.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/hud/hud_host.dart';
import 'package:tapedash/ui/hud/hud_settings.dart';
import 'package:tapedash/ui/pages/drive/apex_cluster.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/ui/pages/drive/minimal_cluster.dart';
import 'package:tapedash/ui/pages/drive/money_slots.dart';
import 'package:tapedash/ui/pages/drive/tape_cluster.dart';
import 'package:tapedash/ui/pages/money/money_figure.dart';
import 'package:tapedash/ui/pages/money/money_page.dart';
import 'package:tapedash/ui/pages/money/money_signals.dart';
import 'package:tapedash/ui/pages/pitstop/pit_stop_page.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../design/support/harness.dart';

/// A drive's services and signals on a fake clock, fed by hand.
class Rig {
  Rig({double? price = 100}) {
    clock = FakeClock()..advance(const Duration(seconds: 100));
    vehicle = VehicleState(clock: clock, scheduler: clock);
    app = AppServices.inMemory(price: price);
    connection = ObservableValue(ConnectionStatus.connected);
    services = DriveServices(
      vehicle: vehicle,
      connection: connection,
      app: app,
      clock: clock,
      scheduler: clock,
    );
    motion = ManualMotionClock();
    money = MoneySignals(
      trip: services.computer,
      settings: app.money,
      ledger: app.ledger,
      motion: motion,
      clock: clock,
      recorder: services.recorder,
    );
    signals = DriveSignals(
      vehicle: vehicle,
      motion: motion,
      clock: clock,
      scheduler: clock,
      connection: connection,
      money: money,
    );
  }

  late final FakeClock clock;
  late final VehicleState vehicle;
  late final AppServices app;
  late final ObservableValue<ConnectionStatus> connection;
  late final DriveServices services;
  late final ManualMotionClock motion;
  late final MoneySignals money;
  late final DriveSignals signals;

  void feed(Sensor s, double v) {
    final now = clock.monotonic();
    vehicle.ingest(s, v, at: now, receivedAt: now);
  }

  /// Seconds of driving at [kmh] burning [maf] g/s of air.
  void drive(
    int seconds, {
    double kmh = 60,
    double maf = 8,
    double rpm = 1800,
    bool fuelLevel = true,
  }) {
    for (var i = 0; i < seconds * 5; i++) {
      clock.advance(const Duration(milliseconds: 200));
      motion.tick(0.2);
      feed(Sensor.speed, kmh);
      if (i % 5 == 0) {
        feed(Sensor.rpm, rpm);
        feed(Sensor.throttle, 25);
        feed(Sensor.airFlow, maf);
        if (fuelLevel) feed(Sensor.fuelLevel, 60);
      }
    }
  }

  /// Lets go of everything. The recorder's last writes are not awaited: in a
  /// widget test the futures only complete when the test pumps, and a tear-down
  /// that waited for them would wait forever.
  void close() {
    signals.dispose();
    money.dispose();
    services.close();
    motion.dispose();
    vehicle.dispose();
  }
}

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;

  setUp(() => kit = TapeRenderKit());
  tearDown(() => kit.dispose());

  Rig make({double? price = 100}) {
    final rig = Rig(price: price);
    addTearDown(rig.close);
    return rig;
  }

  group('MoneySignals', () {
    test('the view follows the fuel and the price', () {
      final rig = make(price: null);
      expect(rig.money.view.value, MoneyView.unavailable);
      rig.drive(5);
      expect(rig.money.view.value, MoneyView.litres);
      rig.app.money.setPrice(100);
      expect(rig.money.view.value, MoneyView.rupees);
    });

    test(
      'a car with no fuel level shows the count from the last full tank',
      () async {
        final rig = make();
        rig.drive(5, fuelLevel: false);
        expect(rig.money.hasRemaining.value, isFalse);

        await rig.app.saveFillUp(
          at: rig.clock.now(),
          litres: 38,
          amount: 3800,
          fullTank: true,
        );
        rig.drive(120, fuelLevel: false);
        expect(rig.money.hasRemaining.value, isTrue);
        expect(rig.money.remainingCounted.value, isTrue);
        // 40 L less what the two minutes used: close to full.
        expect(rig.services.computer.remainingLitres.value, closeTo(40, 1));
        expect(rig.services.computer.remainingLitres.value!, lessThan(40));
      },
    );

    test('a car that reports its level is not counted', () {
      final rig = make();
      rig.drive(20);
      expect(rig.money.hasRemaining.value, isTrue);
      expect(rig.money.remainingCounted.value, isFalse);
    });

    test('the cost signal follows the trip', () {
      final rig = make();
      rig.drive(120);
      expect(
        rig.money.cost.value,
        closeTo(rig.services.computer.cost.value!, 0.5),
      );
      expect(rig.money.cost.value, greaterThan(1));
    });

    test('the blocks follow the Money Tape stream', () {
      final rig = make();
      rig.drive(300, maf: 12);
      expect(
        rig.money.blocks.value.length,
        rig.services.computer.blocks.length,
      );
      expect(rig.money.blocks.value.length, greaterThan(3));
    });

    test('the availability flags say what is not there yet', () {
      final rig = make();
      rig.drive(3, kmh: 3);
      expect(rig.money.instantAvailable.value, isFalse, reason: 'below 5 km/h');
      rig.drive(30);
      expect(rig.money.instantAvailable.value, isTrue);
      expect(rig.money.costPerKmAvailable.value, isTrue);
    });

    test('the confidence pips follow the ledger', () async {
      final rig = make();
      expect(rig.money.confidence.value, MoneyConfidence.uncalibrated);
      await rig.app.ledger.recordFillUp(
        at: DateTime(2026),
        litres: 30,
        amount: 3000,
        fullTank: true,
      );
      rig.app.ledger.addEstimate(24);
      await rig.app.ledger.recordFillUp(
        at: DateTime(2026, 1, 3),
        litres: 30,
        amount: 3000,
        fullTank: true,
      );
      expect(rig.money.confidence.value, MoneyConfidence.calibrating);
    });

    test('the parked breakdown rupees are whole, and add up to the trip', () {
      final rig = make();
      rig.drive(60);

      final parts = [for (final s in rig.money.bucketCost.values) s.target];
      final litres = rig.services.computer.bucketLitres.values.fold<double>(
        0,
        (a, b) => a + b,
      );
      final total = (litres * rig.money.pricePerLitre.value!).round();

      for (final p in parts) {
        expect(p, p.roundToDouble(), reason: 'a whole rupee');
      }
      expect(parts.fold<double>(0, (a, b) => a + b), total.toDouble());
    });

    test('the parked breakdown percents are whole, and add up to 100', () {
      final rig = make();
      rig.drive(60);

      final parts = [for (final s in rig.money.bucketPercent.values) s.target];

      for (final p in parts) {
        expect(p, p.roundToDouble());
      }
      expect(parts.fold<double>(0, (a, b) => a + b), 100);
    });

    test(
      'the parked breakdown percents are each bucket\'s share of the fuel',
      () {
        final rig = make();
        rig.drive(60);

        // A minute of steady driving is almost all normal driving: not a quarter
        // of each bucket, which is what the litres came out as when they were
        // rounded to a total of 100 rather than scaled to it.
        final normal = rig.money.bucketPercent[SpendBucket.normal]!.target;
        expect(normal, greaterThan(90));
        expect(rig.money.bucketPercent[SpendBucket.highSpeed]!.target, 0);
      },
    );

    test('the parked breakdown shares add up to 100', () {
      final rig = make();
      rig.drive(60);
      var total = 0.0;
      for (final s in rig.money.bucketPercent.values) {
        total += s.value;
      }
      expect(total, closeTo(100, 1));
    });
  });

  group('MoneyFigure', () {
    Future<void> show(WidgetTester tester, Rig rig, {double size = 40}) async {
      setWindow(tester, const Size(400, 200));
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: rig.motion,
          child: Center(
            child: MoneyFigure(money: rig.money, size: size),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('rupees, with the pips, once there is fuel and a price', (
      tester,
    ) async {
      final rig = make();
      rig.drive(30);
      await show(tester, rig);
      expect(find.byType(MoneyReadout), findsOneWidget);
      expect(find.text('₹'), findsOneWidget);
    });

    testWidgets('litres, with the unit, while there is no price', (
      tester,
    ) async {
      final rig = make(price: null);
      rig.drive(30);
      await show(tester, rig);
      expect(find.byType(MoneyReadout), findsNothing);
      expect(find.text('L'), findsOneWidget);
    });

    testWidgets('a dash when the car gives no fuel figure', (tester) async {
      final rig = make();
      await show(tester, rig);
      expect(find.text(noValue), findsOneWidget);
      expect(find.byType(MoneyReadout), findsNothing);
    });

    testWidgets('the figure does not rebuild for its own numbers', (
      tester,
    ) async {
      final rig = make();
      rig.drive(20);
      await show(tester, rig);
      final before = tester.element(find.byType(MoneyReadout));
      rig.drive(20);
      await tester.pump();
      expect(tester.element(find.byType(MoneyReadout)), same(before));
    });
  });

  group('the Money page', () {
    Future<void> show(
      WidgetTester tester,
      Rig rig, {
      Size size = const Size(720, 360),
      VoidCallback? onPit,
      VoidCallback? onPrice,
    }) async {
      setWindow(tester, size);
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: rig.motion,
          child: MoneyPage(
            signals: rig.signals,
            width: size.width,
            height: size.height,
            onPitStop: onPit,
            onSetPrice: onPrice,
          ),
        ),
      );
      await tester.pump();
    }

    void park(Rig rig) {
      // Speed 0 for five seconds is parked.
      for (var i = 0; i < 70; i++) {
        rig.clock.advance(const Duration(milliseconds: 100));
        rig.motion.tick(0.1);
        rig.feed(Sensor.speed, 0);
      }
    }

    for (final size in const [Size(640, 360), Size(720, 360), Size(800, 360)]) {
      testWidgets(
        'lays out with no exception at ${size.width.toInt()}x360, moving and parked',
        (tester) async {
          final rig = make();
          rig.drive(60);
          await show(tester, rig, size: size);
          expect(tester.takeException(), isNull);
          park(rig);
          rig.motion.tick(2);
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('while moving there are no buttons at all', (tester) async {
      final rig = make();
      rig.drive(30);
      await show(tester, rig, onPit: () {});
      expect(rig.signals.mode.value, DrivingMode.motion);
      expect(find.byType(TapeButton), findsNothing);
    });

    testWidgets('parked, Pit Stop is there and works', (tester) async {
      final rig = make();
      rig.drive(30);
      var opened = 0;
      await show(tester, rig, onPit: () => opened++);
      park(rig);
      rig.motion.tick(2);
      await tester.pump();
      await tester.pump();
      expect(rig.signals.mode.value, DrivingMode.parked);
      await tester.tap(find.widgetWithText(TapeButton, 'PIT STOP'));
      expect(opened, 1);
    });

    testWidgets('with no price, parked, SET FUEL PRICE asks for it', (
      tester,
    ) async {
      final rig = make(price: null);
      rig.drive(30);
      var asked = 0;
      await show(tester, rig, onPrice: () => asked++);
      park(rig);
      rig.motion.tick(2);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.widgetWithText(TapeButton, 'SET FUEL PRICE'));
      expect(asked, 1);
    });

    testWidgets('a car with no fuel figure says money is unavailable', (
      tester,
    ) async {
      final rig = make();
      await show(tester, rig);
      expect(find.textContaining('unavailable'), findsOneWidget);
    });
  });

  group('the clusters with money', () {
    for (final size in const [Size(640, 360), Size(720, 360), Size(800, 360)]) {
      for (final (name, build)
          in <(String, Widget Function(DriveSignals, Size))>[
            (
              'Apex',
              (s, z) =>
                  ApexCluster(signals: s, width: z.width, height: z.height),
            ),
            (
              'Tape',
              (s, z) =>
                  TapeCluster(signals: s, width: z.width, height: z.height),
            ),
            (
              'Minimal',
              (s, z) =>
                  MinimalCluster(signals: s, width: z.width, height: z.height),
            ),
          ]) {
        testWidgets(
          '$name at ${size.width.toInt()}x360 lays out, with and without a price',
          (tester) async {
            setWindow(tester, size);
            for (final price in [100.0, null]) {
              final rig = make(price: price);
              rig.drive(40);
              await tester.pumpWidget(
                tapeHarness(
                  kit: kit,
                  motion: rig.motion,
                  child: build(rig.signals, size),
                ),
              );
              await tester.pump();
              expect(
                tester.takeException(),
                isNull,
                reason: '$name price $price',
              );
            }
          },
        );
      }
    }

    testWidgets('Apex shows the ₹ flank and the trip in the floor', (
      tester,
    ) async {
      final rig = make();
      rig.drive(60);
      const size = Size(720, 360);
      setWindow(tester, size);
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: rig.motion,
          child: ApexCluster(signals: rig.signals, width: 720, height: 360),
        ),
      );
      await tester.pump();
      expect(find.byType(MoneyReadout), findsOneWidget);
      expect(find.text('₹ THIS TRIP'), findsOneWidget);
      expect(find.text('KM'), findsOneWidget);
    });

    for (final size in const [Size(640, 360), Size(720, 360), Size(800, 360)]) {
      testWidgets(
        'the floor has the trip average km/L right after the trip km, at ${size.width.toInt()}x360',
        (tester) async {
          final rig = make();
          rig.drive(90);
          setWindow(tester, size);
          await tester.pumpWidget(
            tapeHarness(
              kit: kit,
              motion: rig.motion,
              child: ApexCluster(
                signals: rig.signals,
                width: size.width,
                height: 360,
              ),
            ),
          );
          await tester.pump();

          final floor = find.byType(TripFloor);
          final km = find.descendant(of: floor, matching: find.text('KM'));
          final average = find.descendant(
            of: floor,
            matching: find.text('KM/L'),
          );
          expect(km, findsOneWidget);
          expect(average, findsOneWidget);
          // Right after: on the same line, to the right of the distance.
          final kmRect = tester.getRect(km);
          final avgRect = tester.getRect(average);
          expect(avgRect.left, greaterThan(kmRect.right));
          expect((avgRect.center.dy - kmRect.center.dy).abs(), lessThan(4));
          // And clear of the eco bar in the middle of the floor.
          final eco = tester.getRect(find.byType(EcoBar));
          expect(avgRect.right, lessThan(eco.left));
          expect(rig.money.kmPerLitre.target, greaterThan(3));
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('until there is a trip to average, the average is a dash', (
      tester,
    ) async {
      final rig = make();
      setWindow(tester, const Size(720, 360));
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: rig.motion,
          child: ApexCluster(signals: rig.signals, width: 720, height: 360),
        ),
      );
      await tester.pump();
      rig.drive(3, kmh: 0);
      await tester.pump();

      expect(rig.money.kmPerLitreAvailable.value, isFalse);
      expect(
        find.descendant(
          of: find.byType(TripFloor),
          matching: find.text(noValue),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a car with no fuel figure has no average km/L in the floor', (
      tester,
    ) async {
      final rig = make(price: null);
      setWindow(tester, const Size(720, 360));
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: rig.motion,
          child: ApexCluster(signals: rig.signals, width: 720, height: 360),
        ),
      );
      await tester.pump();

      expect(rig.money.view.value, MoneyView.unavailable);
      expect(
        find.descendant(
          of: find.byType(TripFloor),
          matching: find.text('KM/L'),
        ),
        findsNothing,
      );
    });

    testWidgets(
      'a bare cluster (no trip computer) leaves the money slots empty',
      (tester) async {
        final rig = Rig();
        addTearDown(rig.close);
        final bare = DriveSignals(
          vehicle: rig.vehicle,
          motion: rig.motion,
          clock: rig.clock,
          scheduler: rig.clock,
          connection: rig.connection,
        );
        addTearDown(bare.dispose);
        setWindow(tester, const Size(720, 360));
        await tester.pumpWidget(
          tapeHarness(
            kit: kit,
            motion: rig.motion,
            child: ApexCluster(signals: bare, width: 720, height: 360),
          ),
        );
        await tester.pump();
        expect(find.byType(MoneyReadout), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('the numpad', () {
    testWidgets('twelve keys, each reporting its own', (tester) async {
      setWindow(tester, const Size(400, 400));
      final keys = <String>[];
      final motion = ManualMotionClock();
      addTearDown(motion.dispose);
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          child: Center(child: TapeNumpad(onKey: keys.add)),
        ),
      );
      for (final k in ['1', '5', '9', '0', '.']) {
        await tester.tap(find.text(k));
      }
      await tester.tap(find.byType(TapeNumpad).first, warnIfMissed: false);
      expect(keys.take(5), ['1', '5', '9', '0', '.']);
    });

    testWidgets('keys are 72 lp, and at least the 48 lp touch target', (
      tester,
    ) async {
      setWindow(tester, const Size(400, 400));
      final motion = ManualMotionClock();
      addTearDown(motion.dispose);
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          child: Center(child: TapeNumpad(onKey: (_) {})),
        ),
      );
      final size = tester.getSize(find.byType(TapeNumpad));
      expect(size.width, TapeNumpad.widthFor(72));
      expect(size.height, TapeNumpad.heightFor(72));
    });
  });

  group('Pit Stop', () {
    Future<PitStopPageState> show(
      WidgetTester tester,
      ValueNotifier<DrivingMode> mode, {
      Future<void> Function(PitStopForm)? onSave,
      VoidCallback? onClose,
      bool priceOnly = false,
      Size size = const Size(640, 360),
    }) async {
      setWindow(tester, size);
      final motion = ManualMotionClock();
      addTearDown(motion.dispose);
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          child: PitStopPage(
            width: size.width,
            height: size.height,
            mode: mode,
            onSave: onSave ?? (_) async {},
            onClose: onClose ?? () {},
            priceOnly: priceOnly,
            currentPrice: 102.5,
          ),
        ),
      );
      await tester.pump();
      return tester.state<PitStopPageState>(find.byType(PitStopPage));
    }

    Future<void> type(WidgetTester tester, String keys) async {
      for (final k in keys.split('')) {
        await tester.tap(find.text(k).first);
        await tester.pump();
      }
    }

    for (final size in const [Size(640, 360), Size(720, 360), Size(800, 360)]) {
      testWidgets('fits ${size.width.toInt()}x360 with no overflow', (
        tester,
      ) async {
        final mode = ValueNotifier(DrivingMode.parked);
        addTearDown(mode.dispose);
        await show(tester, mode, size: size);
        expect(tester.takeException(), isNull);
        for (final b in find.byType(TapeButton).evaluate()) {
          final r = tester.getRect(find.byWidget(b.widget));
          expect(r.bottom, lessThanOrEqualTo(size.height));
        }
      });
    }

    testWidgets(
      'Save is off until the form is good, and then saves what was typed',
      (tester) async {
        final mode = ValueNotifier(DrivingMode.parked);
        addTearDown(mode.dispose);
        PitStopForm? saved;
        final state = await show(tester, mode, onSave: (f) async => saved = f);
        TapeButton save() =>
            tester.widget<TapeButton>(find.widgetWithText(TapeButton, 'SAVE'));
        expect(save().enabled, isFalse);
        await type(tester, '20');
        expect(save().enabled, isFalse, reason: 'no amount yet');
        await tester.tap(find.text('AMOUNT PAID'));
        await tester.pump();
        await type(tester, '2050');
        expect(save().enabled, isTrue);
        await tester.tap(find.text('₹102.50 a litre'), warnIfMissed: false);
        await tester.tap(find.widgetWithText(TapeButton, 'SAVE'));
        await tester.pump();
        await tester.pump();
        expect(saved, isNotNull);
        expect(saved!.litres, 20);
        expect(saved!.amount, 2050);
        expect(saved!.fullTank, isTrue);
        expect(state.isSaving, isTrue);
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets('the live price is shown as it is typed', (tester) async {
      final mode = ValueNotifier(DrivingMode.parked);
      addTearDown(mode.dispose);
      await show(tester, mode);
      await type(tester, '20');
      await tester.tap(find.text('AMOUNT PAID'));
      await tester.pump();
      await type(tester, '2050');
      expect(find.text('₹102.50 a litre'), findsOneWidget);
    });

    testWidgets('too much for the tank is said, not saved', (tester) async {
      final mode = ValueNotifier(DrivingMode.parked);
      addTearDown(mode.dispose);
      await show(tester, mode);
      await type(tester, '99');
      await tester.tap(find.text('AMOUNT PAID'));
      await tester.pump();
      await type(tester, '9999');
      expect(find.text('That is more than your tank holds.'), findsOneWidget);
      expect(
        tester
            .widget<TapeButton>(find.widgetWithText(TapeButton, 'SAVE'))
            .enabled,
        isFalse,
      );
    });

    testWidgets(
      'the price-only form has one field and a plausible price saves',
      (tester) async {
        final mode = ValueNotifier(DrivingMode.parked);
        addTearDown(mode.dispose);
        PitStopForm? saved;
        await show(
          tester,
          mode,
          priceOnly: true,
          onSave: (f) async => saved = f,
        );
        expect(find.text('LITRES'), findsNothing);
        await type(tester, '102.5');
        await tester.tap(find.widgetWithText(TapeButton, 'SAVE'));
        await tester.pump();
        await tester.pump();
        expect(saved!.priceOnly, isTrue);
        expect(saved!.pricePerLitre, 102.5);
        await tester.pump(const Duration(seconds: 2));
      },
    );

    testWidgets('it closes the moment the car moves', (tester) async {
      final mode = ValueNotifier(DrivingMode.parked);
      addTearDown(mode.dispose);
      var closed = 0;
      await show(tester, mode, onClose: () => closed++);
      mode.value = DrivingMode.motion;
      expect(closed, 1);
    });

    testWidgets('it will not save while moving', (tester) async {
      final mode = ValueNotifier(DrivingMode.parked);
      addTearDown(mode.dispose);
      var saves = 0;
      await show(tester, mode, onSave: (_) async => saves++, onClose: () {});
      await type(tester, '20');
      await tester.tap(find.text('AMOUNT PAID'));
      await tester.pump();
      await type(tester, '2050');
      mode.value = DrivingMode.motion;
      await tester.tap(find.widgetWithText(TapeButton, 'SAVE'));
      await tester.pump();
      expect(saves, 0);
    });
  });

  group('the HUD\'s money layouts', () {
    Future<void> show(WidgetTester tester, Rig rig) async {
      setWindow(tester, const Size(720, 360));
      final settings = HudSettings(active: true, layout: HudLayout.money);
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: rig.motion,
          child: HudHost(
            settings: settings,
            signals: rig.signals,
            money: rig.money,
            width: 720,
            height: 360,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets(
      'with a price and fuel, the ₹ is shown and nothing says unavailable',
      (tester) async {
        final rig = make();
        rig.drive(60);
        await show(tester, rig);
        expect(find.text('MONEY UNAVAILABLE'), findsNothing);
        expect(find.text('₹'), findsWidgets);
      },
    );

    testWidgets(
      'with no fuel figure it says so, and does not invent a number',
      (tester) async {
        final rig = make();
        await show(tester, rig);
        expect(find.text('MONEY UNAVAILABLE'), findsOneWidget);
      },
    );

    testWidgets('with fuel and no price it asks for the price', (tester) async {
      final rig = make(price: null);
      rig.drive(30);
      await show(tester, rig);
      expect(find.text('SET A FUEL PRICE'), findsOneWidget);
      expect(find.text('MONEY UNAVAILABLE'), findsNothing);
    });
  });
}
