// First launch (DESIGN.md 7.11): the cold open's length and drawing, the
// wordmark, the choice, the benchmark hand-off, and the demo path into the
// drive on a fake clock.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/brand/wordmark.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/ui/onboarding/onboarding_screen.dart';
import 'package:tapedash/ui/pages/drive/drive_page.dart';

import '../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;
  late ManualMotionClock motion;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
  });

  tearDown(() {
    motion.dispose();
    kit.dispose();
  });

  void run(int ms) {
    var left = ms * 1000;
    while (left > 0) {
      final step = left < 16667 ? left : 16667;
      motion.tick(step / 1e6);
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

  bool lit(int p) =>
      ((p >> 24) & 0xFF) + ((p >> 16) & 0xFF) + ((p >> 8) & 0xFF) > 90;

  Future<void> show(
    WidgetTester tester, {
    VoidCallback? onDemo,
    VoidCallback? onConnect,
    void Function(List<double>)? onBenchmark,
    bool skip = false,
  }) async {
    setWindow(tester, const Size(720, 360));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: OnboardingScreen(
          width: 720,
          height: 360,
          skipColdOpen: skip,
          onDemo: onDemo ?? () {},
          onConnect: onConnect,
          onBenchmark: onBenchmark,
        ),
      ),
    );
  }

  test('the cold open is at most 1.2 s (DESIGN.md 7.11)', () {
    expect(TapeDurations.cinematic, const Duration(milliseconds: 1200));
  });

  test(
    'the tape fades to nothing at both ends and is full over the middle',
    () {
      expect(TapeLinePainter.alphaAt(0), 0);
      expect(TapeLinePainter.alphaAt(1), 0);
      expect(TapeLinePainter.alphaAt(0.5), 1);
      expect(TapeLinePainter.alphaAt(0.3), 1);
      expect(TapeLinePainter.alphaAt(0.1), closeTo(0.4, 1e-9));
    },
  );

  testWidgets('the line draws outwards from the centre, then the wordmark', (
    tester,
  ) async {
    await show(tester);
    await tester.pump();
    expect(lit((await pixels(tester))[360 * 1440 + 720]), isFalse);

    run(200);
    await tester.pump();
    var px = await pixels(tester);
    // Somewhere in the band of the line, near the centre and not yet far out.
    int extent(Uint32List px) {
      var lo = 1 << 30, hi = -1;
      for (var y = 0; y < 720; y++) {
        for (var x = 0; x < 1440; x++) {
          if (lit(px[y * 1440 + x]) && y > 268 && y < 320) {
            if (x < lo) lo = x;
            if (x > hi) hi = x;
          }
        }
      }
      return hi < 0 ? 0 : hi - lo;
    }

    final early = extent(px);
    run(400);
    await tester.pump();
    px = await pixels(tester);
    final later = extent(px);
    expect(early, greaterThan(0));
    expect(later, greaterThan(early));

    // The line is centred.
    var lo = 1 << 30, hi = -1;
    for (var y = 268; y < 320; y++) {
      for (var x = 0; x < 1440; x++) {
        if (lit(px[y * 1440 + x])) {
          if (x < lo) lo = x;
          if (x > hi) hi = x;
        }
      }
    }
    expect((lo + hi) / 2, closeTo(720, 8));
    run(900);
    await tester.pump();
  });

  testWidgets('the choice is not pressable during the cold open', (
    tester,
  ) async {
    var demos = 0;
    await show(tester, onDemo: () => demos++);
    await tester.pump();
    run(400);
    await tester.pump();
    final state = tester.state<OnboardingScreenState>(
      find.byType(OnboardingScreen),
    );
    expect(state.choiceReady, isFalse);
    await tester.tap(find.text('TRY A DEMO DRIVE'), warnIfMissed: false);
    expect(demos, 0);
    run(1500);
    await tester.pump();
    expect(state.choiceReady, isTrue);
    await tester.pump();
  });

  testWidgets('the benchmark is handed over once, when the cold open ends', (
    tester,
  ) async {
    var calls = 0;
    await show(tester, onBenchmark: (_) => calls++);
    await tester.pump();
    run(1100);
    await tester.pump();
    expect(calls, 0);
    run(200);
    await tester.pump();
    expect(calls, 1);
    run(2000);
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets(
    'after the cold open: demo is primary and works, and connect waits with no flow',
    (tester) async {
      var demos = 0;
      await show(tester, onDemo: () => demos++);
      await tester.pump();
      run(3000);
      await tester.pump();
      final demo = tester.widget<TapeButton>(
        find.widgetWithText(TapeButton, 'TRY A DEMO DRIVE'),
      );
      final connect = tester.widget<TapeButton>(
        find.widgetWithText(TapeButton, 'CONNECT MY CAR'),
      );
      expect(demo.primary, isTrue);
      expect(demo.enabled, isTrue);
      expect(connect.enabled, isFalse);
      expect(
        find.text('ADAPTER SETUP ARRIVES IN A LATER UPDATE'),
        findsOneWidget,
      );
      await tester.tap(find.text('TRY A DEMO DRIVE'));
      expect(demos, 1);
    },
  );

  testWidgets('with a connect flow to offer, CONNECT MY CAR starts it', (
    tester,
  ) async {
    var connects = 0;
    await show(tester, onConnect: () => connects++);
    await tester.pump();
    run(3000);
    await tester.pump();
    final connect = tester.widget<TapeButton>(
      find.widgetWithText(TapeButton, 'CONNECT MY CAR'),
    );
    expect(connect.enabled, isTrue);
    expect(find.text('ADAPTER SETUP ARRIVES IN A LATER UPDATE'), findsNothing);
    await tester.tap(find.text('CONNECT MY CAR'));
    expect(connects, 1);
  });

  testWidgets('skipping the cold open shows the choice at once', (
    tester,
  ) async {
    await show(tester, skip: true);
    await tester.pump();
    run(1000);
    await tester.pump();
    final state = tester.state<OnboardingScreenState>(
      find.byType(OnboardingScreen),
    );
    expect(state.choiceReady, isTrue);
  });

  for (final width in [640.0, 720.0, 800.0]) {
    testWidgets('lays out at ${width.toInt()}x360 with no overflow', (
      tester,
    ) async {
      setWindow(tester, Size(width, 360));
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          child: OnboardingScreen(
            width: width,
            height: 360,
            skipColdOpen: true,
            onDemo: () {},
          ),
        ),
      );
      run(1500);
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (final b in find.byType(TapeButton).evaluate()) {
        final r = tester.getRect(find.byWidget(b.widget));
        expect(r.left, greaterThanOrEqualTo(0));
        expect(r.right, lessThanOrEqualTo(width));
        expect(r.height, greaterThanOrEqualTo(48));
      }
    });
  }

  testWidgets('the demo path: choice, then a live drive with ignition', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final clock = FakeClock()..advance(const Duration(seconds: 100));
    await tester.pumpWidget(
      TapeDashApp(clock: clock, scheduler: clock, skipColdOpen: true),
    );
    // The choice is up for a few seconds, and the drive connects behind it.
    for (var i = 0; i < 50; i++) {
      clock.advance(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(DrivePage), findsNothing);
    await tester.tap(find.text('TRY A DEMO DRIVE'));
    await tester.pump();
    expect(find.byType(DrivePage), findsOneWidget);
    final drive = tester.widget<DrivePage>(find.byType(DrivePage));
    // The drive was connecting behind the choice, so the ignition starts
    // within a second of the tap (DESIGN.md 7.11).
    var ms = 0;
    while (!drive.signals.ignition.hasPlayed && ms < 3000) {
      clock.advance(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      ms += 50;
    }
    expect(ms, lessThanOrEqualTo(1000));
    expect(drive.signals.vehicle.rpm.value, isNotNull);
    expect(drive.signals.ignition.hasPlayed, isTrue);
    expect(tester.takeException(), isNull);
  });
}
