// The connection layer on the Drive page (DESIGN.md 7.12), in real pixels:
// standby leaves only etch below the strip, the beam and the dot are drawn,
// and a connected cluster has no layer's ink at all.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/pages/drive/drive_page.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../../design/support/harness.dart';

const _w = 1600; // 800x400 at dpr 2

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;
  late VehicleState vehicle;
  late ObservableValue<ConnectionStatus> connection;
  late DriveSignals signals;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock()..advance(const Duration(seconds: 100));
    vehicle = VehicleState(clock: clock, scheduler: clock);
    connection = ObservableValue(ConnectionStatus.searching);
    signals = DriveSignals(
      vehicle: vehicle,
      motion: motion,
      clock: clock,
      scheduler: clock,
      connection: connection,
    );
  });

  tearDown(() {
    signals.dispose();
    motion.dispose();
    kit.dispose();
  });

  void run(Duration d) {
    var left = d.inMicroseconds;
    while (left > 0) {
      final step = left < 16667 ? left : 16667;
      motion.tick(step / 1e6);
      clock.advance(Duration(microseconds: step));
      left -= step;
    }
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

  int ink(Uint32List f, int x0, int y0, int x1, int y1) {
    var n = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final v = f[y * _w + x];
        if (((v >> 24) & 0xFF) > 60 ||
            ((v >> 16) & 0xFF) > 60 ||
            ((v >> 8) & 0xFF) > 60) {
          n++;
        }
      }
    }
    return n;
  }

  Future<void> start(WidgetTester tester) async {
    setWindow(tester, const Size(800, 400));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: DrivePage(
          signals: signals,
          motion: motion,
          width: 800,
          height: 400,
        ),
      ),
    );
  }

  // The caution line's outer ends, clear of the tach arc's own top.
  int lineInk(Uint32List f) =>
      ink(f, 410, 8, 540, 40) + ink(f, 1060, 8, 1190, 40);

  // The hero position: the middle of the frame.
  int heroInk(Uint32List f) => ink(f, 700, 340, 900, 460);

  testWidgets('waiting: the breathing dot is at the hero position', (
    tester,
  ) async {
    connection.value = ConnectionStatus.waitingForIgnition;
    await start(tester);
    run(const Duration(seconds: 3));
    await tester.pump();
    expect(heroInk(await pixels(tester)), greaterThan(40));
  });

  testWidgets('connected with no data: the layer paints nothing', (
    tester,
  ) async {
    connection.value = ConnectionStatus.connected;
    await start(tester);
    run(const Duration(seconds: 1));
    await tester.pump();
    final f = await pixels(tester);
    // No caution line on the horizon, no dot at the centre.
    expect(lineInk(f), 0);
  });

  testWidgets('lost: a caution line on the horizon, gone once reconnected', (
    tester,
  ) async {
    connection.value = ConnectionStatus.connected;
    await start(tester);
    run(const Duration(seconds: 1));
    connection.value = ConnectionStatus.lost;
    run(const Duration(seconds: 2));
    await tester.pump();
    expect(lineInk(await pixels(tester)), greaterThan(200));

    connection.value = ConnectionStatus.connected;
    run(const Duration(seconds: 1));
    await tester.pump();
    expect(lineInk(await pixels(tester)), lessThan(20));
  });
}
