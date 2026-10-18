// The Insights pages, on made-up driving (test/support/insight_fixture.dart),
// at the three screen sizes. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/money/fill_up.dart';
import 'package:tapedash/money/fuel_ledger.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/pages/insights/insights_page.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../../support/insight_fixture.dart';
import '../../support/insights_rig.dart';
import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  Future<void> capture(
    WidgetTester tester,
    InsightTab tab,
    String name, {
    Size size = const Size(640, 360),
    Livery? livery,
    bool manual = true,
    bool year = false,
    bool pulls = false,
  }) async {
    setWindow(tester, size);
    final kit = TapeRenderKit();
    addTearDown(kit.dispose);
    final motion = ManualMotionClock();
    addTearDown(motion.dispose);
    final ledger = FuelLedger(
      fills: MemoryFillUpRepository(),
      store: MemoryKeyValueStore(),
    );
    await ledger.recordFillUp(
      at: DateTime(2026, 10, 3),
      litres: 38,
      amount: 4370,
      fullTank: true,
    );
    await ledger.recordFillUp(
      at: DateTime(2026, 10, 10),
      litres: 33,
      amount: 3795,
      fullTank: true,
    );
    ledger.addEstimate(23.6);
    final data = madeInsightData(manual: manual, year: year, pulls: pulls);
    final mode = ValueNotifier(DrivingMode.parked);
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: livery ?? Liveries.ion),
        child: insightsPageFor(
          data: data,
          ledger: ledger,
          mode: mode,
          size: size,
          tab: tab,
          rest: madeRestReadings(DateTime(2026, 10, 17)),
          selected: data.trips.first,
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      motion.tick(0.05);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await capturePng(tester, name);
  }

  testWidgets('tank', (tester) async {
    await capture(tester, InsightTab.tank, 'insights-tank');
  }, skip: !enabled);

  testWidgets('powerflow', (tester) async {
    await capture(tester, InsightTab.powerflow, 'insights-powerflow');
  }, skip: !enabled);

  testWidgets('power', (tester) async {
    await capture(tester, InsightTab.power, 'insights-power', pulls: true);
  }, skip: !enabled);

  testWidgets('current', (tester) async {
    await capture(tester, InsightTab.current, 'insights-current');
  }, skip: !enabled);
}
