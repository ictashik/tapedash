// Diagnostics (DESIGN.md 7.10) on a fake source: the adapter panel, the PID matrix,
// the fault codes with their descriptions, and CLEAR CODES as a slide to confirm.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/fuel/fuel_estimator.dart' show FuelSource;
import 'package:tapedash/obd/diagnostics_source.dart';
import 'package:tapedash/obd/dtc/dtc.dart';
import 'package:tapedash/obd/dtc/dtc_descriptions.dart';
import 'package:tapedash/obd/elm327/elm327_failure.dart';
import 'package:tapedash/ui/design/components/controls/slide_to_confirm.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/pages/diagnostics/diagnostics_page.dart';
import 'package:tapedash/vehicle/reading.dart';
import 'package:tapedash/vehicle/vehicle_state.dart' show DrivingMode;

import '../design/support/harness.dart';

class FakeDiagnostics implements DiagnosticsSource {
  final ObservableValue<AdapterInfo?> info = ObservableValue(null);
  final ObservableValue<double> rate = ObservableValue(0);
  final ObservableValue<FuelSource> fuel = ObservableValue(FuelSource.none);
  final ObservableValue<Reading?> volts = ObservableValue(null);

  DtcReadResult result = const DtcReadResult();
  DtcClearOutcome outcome = DtcClearOutcome.cleared;
  int reads = 0;
  int clears = 0;

  @override
  Observable<AdapterInfo?> get adapterInfo => info;
  @override
  Observable<double> get pollRate => rate;
  @override
  Observable<FuelSource> get fuelSource => fuel;
  @override
  Observable<Reading?> get voltage => volts;

  @override
  void readCodes(void Function(DtcReadResult result) done) {
    reads++;
    done(result);
  }

  @override
  void clearCodes(void Function(DtcClearOutcome outcome) done) {
    clears++;
    if (outcome == DtcClearOutcome.cleared) result = const DtcReadResult();
    done(outcome);
  }
}

AdapterInfo adapter({Set<int>? pids}) => AdapterInfo(
  banner: 'ELM327 v1.5',
  protocolNumber: '6',
  supportedPids: pids ?? {0x04, 0x05, 0x0C, 0x0D, 0x11},
  ecuCount: 1,
  retries: 0,
  warnings: const [],
);

void main() {
  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeDiagnostics source;
  late ValueNotifier<DrivingMode> mode;
  late DtcDescriptions descriptions;
  var closed = 0;

  setUpAll(() async {
    await loadTapeFonts();
  });

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    source = FakeDiagnostics();
    mode = ValueNotifier(DrivingMode.parked);
    descriptions = DtcDescriptions.parse(
      '{"P0420":"Catalytic converter working below its threshold (bank 1)",'
      '"P0171":"Mixture too lean (bank 1)"}',
    );
    closed = 0;
  });

  tearDown(() {
    kit.dispose();
    motion.dispose();
    mode.dispose();
  });

  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(720, 360),
  }) async {
    setWindow(tester, size);
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: DiagnosticsPage(
          source: source,
          mode: mode,
          width: size.width,
          height: size.height,
          onClose: () => closed++,
          descriptions: descriptions,
        ),
      ),
    );
    await tester.pump();
  }

  for (final size in const [Size(640, 360), Size(720, 360), Size(800, 360)]) {
    testWidgets(
      'lays out at ${size.width.toInt()}x360, with and without a car',
      (tester) async {
        await show(tester, size: size);
        expect(find.text('No car connected yet.'), findsOneWidget);
        expect(tester.takeException(), isNull);

        source.result = const DtcReadResult(
          stored: [Dtc('P0420')],
          pending: [Dtc('P0171')],
        );
        source.info.value = adapter();
        source.fuel.value = FuelSource.airFlow;
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('the adapter panel says what the adapter and the car are', (
    tester,
  ) async {
    source.info.value = adapter();
    source.fuel.value = FuelSource.speedDensity;
    await show(tester);
    source.rate.value = 4.2;
    source.volts.value = const Reading(
      value: 14.1,
      at: Duration.zero,
      receivedAt: Duration.zero,
    );
    await tester.pump();
    expect(find.text('ELM327 v1.5'), findsOneWidget);
    expect(find.textContaining('ISO 15765-4 CAN'), findsOneWidget);
    expect(find.text('MAP'), findsOneWidget);
    expect(find.text('14.1 V'), findsOneWidget);
    expect(find.text('4.2 /s'), findsOneWidget);
    expect(find.text('5 of 96'), findsOneWidget);
  });

  testWidgets('a tap on a cell of the PID matrix names the PID', (
    tester,
  ) async {
    source.info.value = adapter();
    await show(tester);
    final matrix = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is PidMatrixPainter,
    );
    final size = tester.getSize(matrix);
    final origin = tester.getTopLeft(matrix);
    // PID 0C: the twelfth cell of the first row.
    final cellW = (size.width - PidMatrixPainter.gap * 15) / 16;
    final at =
        origin +
        Offset(11 * (cellW + PidMatrixPainter.gap) + cellW / 2, cellW / 2);
    await tester.tapAt(at);
    await tester.pump();
    expect(find.textContaining('0C  Engine speed'), findsOneWidget);
    expect(find.textContaining('the car answers'), findsOneWidget);

    // An unsupported one says so.
    final other = origin + Offset(cellW / 2, cellW / 2);
    await tester.tapAt(other);
    await tester.pump();
    expect(find.textContaining('01  Not one TapeDash reads'), findsOneWidget);
    expect(find.textContaining('no answer'), findsOneWidget);
  });

  testWidgets('the codes are read when the page opens, with what they mean', (
    tester,
  ) async {
    source.result = const DtcReadResult(
      stored: [Dtc('P0420')],
      pending: [Dtc('P0171')],
    );
    source.info.value = adapter();
    await show(tester);
    expect(source.reads, 1);
    expect(find.text('P0420'), findsOneWidget);
    expect(find.textContaining('Catalytic converter'), findsOneWidget);
    expect(find.text('STORED'), findsOneWidget);
    expect(find.text('P0171'), findsOneWidget);
    expect(find.text('PENDING'), findsOneWidget);
  });

  testWidgets('a car that answers while the page is open is read at once', (
    tester,
  ) async {
    await show(tester);
    expect(source.reads, 0);
    source.result = const DtcReadResult(stored: [Dtc('P0420')]);
    source.info.value = adapter();
    await tester.pump();
    await tester.pump();
    expect(source.reads, 1);
    expect(find.text('P0420'), findsOneWidget);
  });

  testWidgets('no codes, and a failed read, are said in words', (tester) async {
    source.info.value = adapter();
    await show(tester);
    expect(find.text('No fault codes.'), findsOneWidget);

    source.result = const DtcReadResult(failure: Elm327Failure.noData);
    await tester.tap(find.text('READ'));
    await tester.pump();
    expect(find.textContaining('did not answer'), findsOneWidget);
  });

  testWidgets('clear codes needs a full slide, then clears and reads again', (
    tester,
  ) async {
    source.result = const DtcReadResult(stored: [Dtc('P0420')]);
    source.info.value = adapter();
    await show(tester);
    final slider = find.byType(SlideToConfirm);
    final start = tester.getTopLeft(slider) + const Offset(30, 28);

    // Part-way: nothing.
    var drag = await tester.startGesture(start);
    await drag.moveBy(const Offset(60, 0));
    await drag.up();
    await tester.pump();
    expect(source.clears, 0);
    motion.advance(const Duration(seconds: 2));
    await tester.pump();

    // All the way: cleared, and read again.
    drag = await tester.startGesture(start);
    await drag.moveBy(Offset(tester.getSize(slider).width, 0));
    await drag.up();
    await tester.pump();
    expect(source.clears, 1);
    expect(source.reads, 2);
    expect(find.text('The codes are cleared.'), findsOneWidget);
    expect(find.text('No fault codes.'), findsOneWidget);
  });

  testWidgets('with no codes the slide is disabled', (tester) async {
    source.info.value = adapter();
    await show(tester);
    final start =
        tester.getTopLeft(find.byType(SlideToConfirm)) + const Offset(30, 28);
    final drag = await tester.startGesture(start);
    await drag.moveBy(const Offset(600, 0));
    await drag.up();
    await tester.pump();
    expect(source.clears, 0);
  });

  testWidgets('a car that refuses is told to the user, not hidden', (
    tester,
  ) async {
    source.result = const DtcReadResult(stored: [Dtc('P0420')]);
    source.outcome = DtcClearOutcome.refusedByEcu;
    source.info.value = adapter();
    await show(tester);
    final slider = find.byType(SlideToConfirm);
    final drag = await tester.startGesture(
      tester.getTopLeft(slider) + const Offset(30, 28),
    );
    await drag.moveBy(Offset(tester.getSize(slider).width, 0));
    await drag.up();
    await tester.pump();
    expect(find.textContaining('would not clear them'), findsOneWidget);
    expect(find.text('P0420'), findsOneWidget);
  });

  testWidgets('it closes itself when the car starts to move', (tester) async {
    source.info.value = adapter();
    await show(tester);
    expect(closed, 0);
    mode.value = DrivingMode.motion;
    await tester.pump();
    expect(closed, 1);
  });

  testWidgets('Close closes', (tester) async {
    await show(tester);
    await tester.tap(find.text('CLOSE'));
    await tester.pump();
    expect(closed, 1);
  });
}
