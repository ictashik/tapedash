// The debug overlay (CLAUDE.md 9): a long-press on the driving screen opens it, it
// shows the frame rate, poll rate, fuel source, tier and battery, it opens the
// Design Lab, and its Close puts it away. Never shown by itself.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/platform/fake_device_features.dart';
import 'package:tapedash/ui/design/render/tape_fonts.dart';
import 'package:tapedash/ui/dev/debug_overlay.dart';
import 'package:tapedash/ui/lab/design_lab.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => TapeFonts.load());

  late FakeClock clock;
  late FakeDeviceFeatures device;

  setUp(() {
    clock = FakeClock()..advance(const Duration(seconds: 100));
    device = FakeDeviceFeatures()..batteryTemperature = 37.5;
  });

  tearDown(() => device.dispose());

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TapeDashApp(
        clock: clock,
        scheduler: clock,
        onboarding: false,
        services: await AppServices.memory(),
        device: device,
        scenario: 'cold_start_idle',
      ),
    );
    for (var i = 0; i < 20; i++) {
      clock.advance(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('it is not there until a long-press, and a long-press opens it', (
    tester,
  ) async {
    await boot(tester);
    expect(find.byType(DebugOverlay), findsNothing);
    await tester.longPressAt(const Offset(360, 180));
    await tester.pump();
    expect(find.byType(DebugOverlay), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('it shows what the handoff asks for', (tester) async {
    await boot(tester);
    await tester.longPressAt(const Offset(360, 180));
    await tester.pump();
    for (final label in [
      'SOURCE',
      'LINK',
      'POLL RATE',
      'FUEL FROM',
      'FRAMES',
      'TIER',
      'MODE',
      'BATTERY',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.textContaining('37.5'), findsOneWidget);
    expect(find.textContaining('BALANCED'), findsOneWidget);
    expect(find.textContaining('DEMO'), findsWidgets);
  });

  testWidgets('Close puts it away', (tester) async {
    await boot(tester);
    await tester.longPressAt(const Offset(360, 180));
    await tester.pump();
    await tester.tap(find.text('CLOSE'));
    await tester.pump();
    expect(find.byType(DebugOverlay), findsNothing);
  });

  testWidgets('Design Lab opens the lab, and the overlay goes', (tester) async {
    await boot(tester);
    await tester.longPressAt(const Offset(360, 180));
    await tester.pump();
    await tester.tap(find.text('DESIGN LAB').first);
    await tester.pump();
    await tester.pump();
    expect(find.byType(DesignLab), findsOneWidget);
    expect(find.byType(DebugOverlay), findsNothing);
  });

  testWidgets('a short tap and a double-tap do not open it', (tester) async {
    await boot(tester);
    await tester.tapAt(const Offset(360, 180));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DebugOverlay), findsNothing);
  });
}
