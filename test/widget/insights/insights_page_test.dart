import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/insights/insight_data.dart';
import 'package:tapedash/insights/tank_reading.dart';
import 'package:tapedash/money/fill_up.dart';
import 'package:tapedash/money/fuel_ledger.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/pages/insights/insights_page.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../../design/support/harness.dart';
import '../../support/insight_fixture.dart';

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
        child: InsightsPage(
          load: () async => data,
          tank: (trips) =>
              TankReading.of(ledger: ledger, tankLitres: 40, trips: trips),
          mode: _Listenable(mode),
          width: size.width,
          height: size.height,
          onClose: () => closed++,
          initial: tab ?? InsightTab.values.first,
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
