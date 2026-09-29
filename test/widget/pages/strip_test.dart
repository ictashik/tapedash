// The Strip (DESIGN.md 7.1): the settle math (the fling, the nearest, the
// lock), the rubber-band's give, the page tape's five ticks with the lock
// marks while moving, the lock glyph after a resisted release, the mount
// window around the settled position, and the strip's own no-rebuild rule.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/ui/pages/strip/placeholder_page.dart';
import 'package:tapedash/ui/pages/strip/the_strip.dart';
import 'package:tapedash/vehicle/vehicle_state.dart' show DrivingMode;

import '../../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;
  late ValueNotifier<DrivingMode> mode;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock()..advance(const Duration(seconds: 100));
    mode = ValueNotifier(DrivingMode.parked);
  });

  tearDown(() {
    motion.dispose();
    kit.dispose();
  });

  const names = ['REVIEW', 'MONEY', 'DRIVE', 'COACH', 'HISTORY'];

  List<Widget> pages() => [
    for (var i = 0; i < 5; i++)
      StripPlaceholder(
        name: names[i],
        note: 'Arrives later.',
        width: 800,
        height: 400,
      ),
  ];

  TheStrip strip() => TheStrip(
    pages: pages(),
    mode: mode,
    motion: motion,
    width: 800,
    height: 400,
  );

  void run(Duration duration) {
    var left = duration.inMicroseconds;
    const frame = 16667;
    while (left > 0) {
      final step = left < frame ? left : frame;
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

  group('the settle math (DESIGN.md 7.1)', () {
    test('a slow release goes to the nearest page', () {
      expect(TheStripState.settleTarget(2.0, 0), 2);
      expect(TheStripState.settleTarget(2.3, 0), 2);
      expect(TheStripState.settleTarget(2.7, 0), 3);
      expect(TheStripState.settleTarget(0.4, 0), 0);
      expect(TheStripState.settleTarget(3.9, 0), 4);
    });

    test('a fling goes one page in its own direction', () {
      // Fast enough to be a fling: the next page in the hand's own
      // direction, from wherever the hand's own raw position was.
      final fast = TapeMotion.pageFlingVelocity * 1.5;
      expect(TheStripState.settleTarget(2.0, fast), 3);
      expect(TheStripState.settleTarget(2.0, -fast), 1);
      // Mid-flight, the fling continues the direction the hand was already
      // moving in.
      expect(TheStripState.settleTarget(2.6, fast), 4);
      expect(TheStripState.settleTarget(2.4, -fast), 1);
      // The strip's own ends hold: no page beyond either.
      expect(TheStripState.settleTarget(0.0, -fast), 0);
      expect(TheStripState.settleTarget(4.0, fast), 4);
    });
  });

  group('the rubber-band (DESIGN.md 7.1)', () {
    test('in range it is the raw itself; past an edge it holds a give', () {
      const give = TapeMotion.lockedSwipeGive;
      expect(TheStripState.resisted(2.0, 0, 4), 2.0);
      // Half a page of pull past a lock gives `give` of a page back.
      expect(TheStripState.resisted(2.5, 1, 2), closeTo(2 + give * 0.5, 1e-9));
      // A whole page of pull does not go further than the give, however far
      // the hand went.
      expect(TheStripState.resisted(4.0, 1, 2), closeTo(2 + give, 1e-9));
      expect(TheStripState.resisted(0.5, 1, 2), closeTo(1 - give * 0.5, 1e-9));
    });
  });

  group('the mounted window (DESIGN.md 7.1)', () {
    testWidgets('a page mounts while it or a neighbour could be on screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        tapeHarness(kit: kit, motion: motion, child: strip()),
      );

      // Settled on Drive: Drive and no one else is mounted.
      expect(find.text('REVIEW'), findsNothing);
      expect(find.text('MONEY'), findsNothing);
      expect(find.text('DRIVE'), findsOneWidget);

      // Past the half-way to Money, held: both pages on screen at once.
      final drag = await tester.startGesture(const Offset(400, 200));
      await drag.moveBy(const Offset(260, 0));
      run(const Duration(milliseconds: 40));
      await drag.moveBy(const Offset(260, 0));
      run(const Duration(milliseconds: 60));
      await tester.pump();
      expect(find.text('MONEY'), findsOneWidget);
      expect(find.text('DRIVE'), findsOneWidget);

      // Settled on Money: Drive is still mounted (it is the home page), the
      // pages a step away are not.
      await drag.up();
      run(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('REVIEW'), findsNothing);
      expect(find.text('MONEY'), findsOneWidget);
      expect(find.text('DRIVE'), findsOneWidget);
      expect(find.text('COACH'), findsNothing);
      expect(find.text('HISTORY'), findsNothing);
    });
  });

  group('the mounted window holds a page through a spring overshoot', () {
    testWidgets('a page swiped towards is mounted from the first pixels', (
      tester,
    ) async {
      await tester.pumpWidget(
        tapeHarness(kit: kit, motion: motion, child: strip()),
      );
      expect(find.text('COACH'), findsNothing);

      // A finger dragged left pulls Coach in from the right.
      final drag = await tester.startGesture(const Offset(400, 200));
      await drag.moveBy(const Offset(-60, 0));
      run(const Duration(milliseconds: 60));
      await tester.pump();
      expect(find.text('COACH'), findsOneWidget);
      expect(find.text('DRIVE'), findsOneWidget);
      await drag.up();
      run(const Duration(seconds: 1));
      await tester.pump();
    });

    testWidgets(
      'Review is not torn down and rebuilt as the strip settles on it',
      (tester) async {
        final log = <String>[];
        final key = GlobalKey<TheStripState>();
        await tester.pumpWidget(
          tapeHarness(
            kit: kit,
            motion: motion,
            child: TheStrip(
              key: key,
              pages: [
                _Probe(log),
                for (var i = 1; i < 5; i++)
                  StripPlaceholder(
                    name: names[i],
                    note: 'Arrives later.',
                    width: 800,
                    height: 400,
                  ),
              ],
              mode: mode,
              motion: motion,
              width: 800,
              height: 400,
            ),
          ),
        );
        expect(log, isEmpty);

        // The page spring overshoots the end it lands on, which puts the offset a
        // hair below 0 for a moment: the page must stay mounted through that.
        key.currentState!.goTo(0);
        var lowest = 0.0;
        for (var i = 0; i < 180; i++) {
          run(const Duration(milliseconds: 16));
          await tester.pump();
          lowest = [
            lowest,
            key.currentState!.debugOffset,
          ].reduce((a, b) => a < b ? a : b);
        }
        expect(
          lowest,
          lessThan(0),
          reason: 'the test only means something if the spring overshoots',
        );
        expect(log, ['init']);
      },
    );
  });

  group('the strip does not rebuild for its own motion', () {
    testWidgets('a page inside the window does not rebuild while the strip '
        'moves within it', (tester) async {
      var builds = 0;
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          child: TheStrip(
            pages: [
              StripPlaceholder(
                name: 'REVIEW',
                note: 'Arrives later.',
                width: 800,
                height: 400,
              ),
              Builder(
                builder: (context) {
                  builds++;
                  return StripPlaceholder(
                    name: 'MONEY',
                    note: 'Arrives later.',
                    width: 800,
                    height: 400,
                  );
                },
              ),
              StripPlaceholder(
                name: 'DRIVE',
                note: 'Arrives later.',
                width: 800,
                height: 400,
              ),
              StripPlaceholder(
                name: 'COACH',
                note: 'Arrives later.',
                width: 800,
                height: 400,
              ),
              StripPlaceholder(
                name: 'HISTORY',
                note: 'Arrives later.',
                width: 800,
                height: 400,
              ),
            ],
            mode: mode,
            motion: motion,
            width: 800,
            height: 400,
          ),
        ),
      );
      builds = 0;

      // A slow drag to Money and back, all inside the two pages' window:
      // the pages themselves never rebuild; the Flow repaints transforms.
      final drag = await tester.startGesture(const Offset(400, 200));
      await drag.moveBy(const Offset(200, 0));
      run(const Duration(milliseconds: 120));
      await drag.moveBy(const Offset(-200, 0));
      run(const Duration(seconds: 2));
      await tester.pump();
      await tester.pump();
      expect(builds, 0);
    });
  });

  group('the page tape (DESIGN.md 7.1)', () {
    const accentCoreArgb = 0x5CE1FFFF;

    // The ticks: five of 10 lp with 12 lp gaps, centred, at the very bottom.
    double tickLeft(int i) => (800 - (5 * 10 + 4 * 12)) / 2 + i * (10 + 12);

    testWidgets('the current page is lit, the rest are etch', (tester) async {
      setWindow(tester, const Size(800, 400));
      mode.value = DrivingMode.parked;
      await tester.pumpWidget(
        tapeHarness(kit: kit, motion: motion, child: strip()),
      );
      await tester.pump();

      final frame = await pixels(tester);
      final width = (800 * tester.view.devicePixelRatio).round();
      final dpr = tester.view.devicePixelRatio;
      final y = ((400 - 4) * dpr).round();

      int accentAt(int i) {
        var count = 0;
        final x0 = (tickLeft(i) * dpr).round();
        for (var dx = 0; dx < 10 * dpr; dx++) {
          if (frame[y * width + x0 + dx] == accentCoreArgb) count++;
        }
        return count;
      }

      // Drive (the home, i = 2) is lit; its neighbours are etch.
      expect(accentAt(2), greaterThan(0));
      expect(accentAt(1), 0);
      expect(accentAt(3), 0);
    });

    int accentIn(int i, Uint32List frame, double dpr, int y) {
      var count = 0;
      final x0 = (tickLeft(i) * dpr).round();
      for (var dx = 0; dx < 10 * dpr; dx++) {
        if (frame[y * ((800 * dpr).round()) + x0 + dx] == accentCoreArgb) {
          count++;
        }
      }
      return count;
    }

    testWidgets('while moving, the locked pages carry the lock', (
      tester,
    ) async {
      setWindow(tester, const Size(800, 400));
      mode.value = DrivingMode.motion;
      await tester.pumpWidget(
        tapeHarness(kit: kit, motion: motion, child: strip()),
      );
      await tester.pump();

      final frame = await pixels(tester);
      final width = (800 * tester.view.devicePixelRatio).round();
      final dpr = tester.view.devicePixelRatio;
      final y = ((400 - 4) * dpr).round();

      int inkAt(int i) {
        var count = 0;
        final x0 = (tickLeft(i) * dpr).round();
        for (var dx = 0; dx < 8 * dpr; dx++) {
          final v = frame[y * width + x0 + dx];
          // The lock's stroke is a 1.17 device-px hairline at this size, so
          // no pixel of it is the pure token colour; it is found by how far
          // it lifts the void, which the etch dash (near black) does not.
          if (((v >> 24) & 0xFF) > 0x30) {
            count++;
          }
        }
        return count;
      }

      // Review, Coach and History carry the lock; Money is an etch dash and
      // Drive (the current page) is lit with the accent.
      expect(inkAt(0), greaterThan(0));
      expect(inkAt(3), greaterThan(0));
      expect(inkAt(4), greaterThan(0));
      expect(inkAt(1), 0);
      expect(accentIn(2, frame, dpr, y), greaterThan(0));
    });
  });

  group('the motion lock (DESIGN.md 7.1)', () {
    testWidgets('a swipe toward a locked page springs back and says why', (
      tester,
    ) async {
      setWindow(tester, const Size(800, 400));
      mode.value = DrivingMode.motion;
      await tester.pumpWidget(
        tapeHarness(kit: kit, motion: motion, child: strip()),
      );
      await tester.pump();

      // The tester's own fling: a real hand's swipe toward the locked
      // Coach, with the release's own velocity, which the strip refuses.
      await tester.flingFrom(
        const Offset(400, 200),
        const Offset(-900, 0),
        2000,
      );
      run(const Duration(milliseconds: 200));
      await tester.pump();

      // The strip is back on Drive, not on the locked Coach.
      final state = tester.state<TheStripState>(find.byType(TheStrip));
      expect(state.offset, closeTo(2, 0.05));

      // And the lock glyph is on screen, above the tape.
      final frame = await pixels(tester);
      final dpr = tester.view.devicePixelRatio;
      final width = (800 * dpr).round();
      var ink = 0;
      for (
        var y = ((400 - 32) * dpr).round();
        y < ((400 - 12) * dpr).round();
        y++
      ) {
        for (var x = (390 * dpr).round(); x < (410 * dpr).round(); x++) {
          if (((frame[y * width + x] >> 24) & 0xFF) > 0x60) ink++;
        }
      }
      expect(ink, greaterThan(0), reason: 'no lock glyph on screen');

      // After the glyph's own 800 ms it is gone.
      run(const Duration(seconds: 1));
      await tester.pump();
      final after = await pixels(tester);
      var still = 0;
      for (
        var y = ((400 - 32) * dpr).round();
        y < ((400 - 12) * dpr).round();
        y++
      ) {
        for (var x = (390 * dpr).round(); x < (410 * dpr).round(); x++) {
          if (((after[y * width + x] >> 24) & 0xFF) > 0x60) still++;
        }
      }
      expect(still, 0, reason: 'the lock glyph stayed past its own 800 ms');
    });

    testWidgets('a page left on when the car starts moving is left at once', (
      tester,
    ) async {
      setWindow(tester, const Size(800, 400));
      await tester.pumpWidget(
        tapeHarness(kit: kit, motion: motion, child: strip()),
      );

      // Onto Coach while parked: the tester's own fling gives the hand's
      // own velocity at the release.
      await tester.flingFrom(
        const Offset(400, 200),
        const Offset(-620, 0),
        2000,
      );
      run(const Duration(seconds: 2));
      await tester.pump();
      final state = tester.state<TheStripState>(find.byType(TheStrip));
      expect(state.offset, closeTo(4, 0.05));

      // The car starts moving: the strip returns to Drive inside the 300 ms
      // the motion return allows.
      mode.value = DrivingMode.motion;
      run(const Duration(milliseconds: 300));
      await tester.pump();
      expect(state.offset, closeTo(2, 0.05));
    });
  });
}

/// A page that says when its state is made and let go.
class _Probe extends StatefulWidget {
  const _Probe(this.log);

  final List<String> log;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.log.add('init');
  }

  @override
  void dispose() {
    widget.log.add('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
