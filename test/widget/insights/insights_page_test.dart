import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/insights/insight_data.dart';
import 'package:tapedash/money/fill_up.dart';
import 'package:tapedash/money/fuel_ledger.dart';
import 'package:tapedash/trips/trip.dart';
import 'package:tapedash/ui/design/components/insights/toll_map_chart.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/pages/insights/insights_page.dart';
import 'package:tapedash/ui/pages/insights/tolls_panel.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../../design/support/harness.dart';
import '../../support/insight_fixture.dart';
import '../../support/insights_rig.dart';

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late ObservableValue<DrivingMode> mode;
  late InsightData data;
  late FuelLedger ledger;
  var closed = 0;

  setUp(() async {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    mode = ObservableValue(DrivingMode.parked);
    data = madeInsightData();
    ledger = FuelLedger(
      fills: MemoryFillUpRepository(),
      store: MemoryKeyValueStore(),
    );
    closed = 0;
  });

  tearDown(() {
    motion.dispose();
    kit.dispose();
  });

  Future<InsightsPageState> show(
    WidgetTester tester, {
    Size size = const Size(640, 360),
    InsightTab? tab,
  }) async {
    setWindow(tester, size);
    final clock = FakeClock();
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: insightsPageFor(
          data: data,
          ledger: ledger,
          mode: _Listenable(mode),
          size: size,
          tab: tab,
          onClose: () => closed++,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(clock.now(), isNotNull);
    return tester.state<InsightsPageState>(find.byType(InsightsPage));
  }

  for (final size in const [Size(640, 360), Size(720, 360), Size(800, 360)]) {
    testWidgets('every tab draws at ${size.width.toInt()}x360', (tester) async {
      final state = await show(tester, size: size);
      for (final tab in InsightTab.values) {
        state.showTab(tab);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: tab.name);
      }
    });
  }

  testWidgets('it reads the trips first, then draws', (tester) async {
    final state = await show(tester);
    expect(state.data, isNotNull);
    expect(state.tab, InsightTab.values.first);
  });

  testWidgets('Close closes', (tester) async {
    await show(tester);
    await tester.tap(find.text('CLOSE'));
    expect(closed, 1);
  });

  testWidgets('it closes itself when the car moves', (tester) async {
    await show(tester);
    mode.value = DrivingMode.motion;
    expect(closed, 1);
  });

  testWidgets('Current: the volts, the dips and an empty battery log', (
    tester,
  ) async {
    await show(tester, tab: InsightTab.current);
    expect(find.text('CHARGING'), findsWidgets);
    expect(find.text('DIPS'), findsOneWidget);
    expect(find.text('None yet'), findsOneWidget);
    expect(find.textContaining('14.0'), findsWidgets);
  });

  testWidgets('Powerflow: the wheels, the brakes and the caveat', (
    tester,
  ) async {
    await show(tester, tab: InsightTab.powerflow);
    expect(find.text('TO THE WHEELS'), findsOneWidget);
    expect(find.textContaining('no hills'), findsOneWidget);
    expect(find.textContaining('≈'), findsWidgets);
  });

  testWidgets('Power: the highest wheel power and the revs it covers', (
    tester,
  ) async {
    await show(tester, tab: InsightTab.power);
    expect(find.text('HIGHEST SEEN'), findsOneWidget);
    expect(find.text('REVS REACHED'), findsOneWidget);
    expect(find.textContaining('kW'), findsWidgets);
  });

  testWidgets('Gears: the gears a made drive used, and none for a CVT', (
    tester,
  ) async {
    await show(tester, tab: InsightTab.gears);
    expect(find.text('GEARS FOUND'), findsOneWidget);
    expect(find.textContaining('No gear sensor'), findsOneWidget);
    expect(find.text('None'), findsNothing);
  });

  testWidgets('Gears: a CVT shows a fan, and says so', (tester) async {
    data = madeInsightData(manual: false);
    final state = await show(tester, tab: InsightTab.gears);
    expect(state.data!.gearbox.isFan, isTrue);
    expect(find.text('None'), findsOneWidget);
    expect(find.textContaining('looks like a CVT'), findsOneWidget);
  });

  testWidgets(
    'Tolls: the dearest place first, and a tap on a ring chooses it',
    (tester) async {
      final state = await show(tester, tab: InsightTab.tolls);
      final panel = tester.state<TollsPanelState>(find.byType(TollsPanel));
      expect(panel.selected, 0);
      expect(find.textContaining('PLACE 1 OF'), findsOneWidget);

      final map = state.data!.tollMap;
      final box = tester.getRect(find.byType(TollMapChart));
      final at = TollMapPainter.positions(map, box.size);
      await tester.tapAt(box.topLeft + at[2]);
      await tester.pump();
      expect(panel.selected, 2);
      expect(find.textContaining('PLACE 3 OF'), findsOneWidget);

      // A tap on empty ground changes nothing.
      await tester.tapAt(box.topLeft + const Offset(4, 4));
      await tester.pump();
      expect(panel.selected, 2);
    },
  );

  testWidgets('Tolls: with no GPS trail it says what fills it in', (
    tester,
  ) async {
    data = InsightData.of([
      for (final (t, s) in data.withSamples)
        (
          t,
          [
            for (final x in s)
              TripSample(
                seconds: x.seconds,
                speedKmh: x.speedKmh,
                rpm: x.rpm,
                throttle: x.throttle,
                litresPerHour: x.litresPerHour,
              ),
          ],
        ),
    ]);
    await show(tester, tab: InsightTab.tolls);
    expect(find.text('NOWHERE YET'), findsOneWidget);
  });

  testWidgets('the tank says what fills it in when nothing is counted', (
    tester,
  ) async {
    await show(tester, tab: InsightTab.tank);
    expect(find.textContaining('FULL TANK'), findsOneWidget);
  });

  testWidgets('the tank shows litres and range once a full tank is logged', (
    tester,
  ) async {
    await ledger.recordFillUp(
      at: DateTime(2026, 10, 1),
      litres: 38,
      amount: 4370,
      fullTank: true,
    );
    ledger.addEstimate(23.6);
    await show(tester, tab: InsightTab.tank);
    expect(find.textContaining('≈ 16'), findsOneWidget);
    expect(find.textContaining('KM'), findsWidgets);
  });
}

class _Listenable extends ValueNotifier<DrivingMode> {
  _Listenable(this.source) : super(source.value) {
    source.addListener(_sync);
  }

  final ObservableValue<DrivingMode> source;

  void _sync() => value = source.value;

  @override
  void dispose() {
    source.removeListener(_sync);
    super.dispose();
  }
}
