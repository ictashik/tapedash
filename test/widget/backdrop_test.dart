// The canvas (DESIGN.md 4.1), the static layers it is cached in (9.3), and the
// motion scope.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/motion_scope.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/render/static_layer.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';

import '../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;

  setUp(() => kit = TapeRenderKit());
  tearDown(() => kit.dispose());

  Future<ByteData> pixelsOf(WidgetTester tester) async {
    final image = await renderImage(tester);
    late ByteData data;
    await tester.runAsync(() async => data = (await image.toByteData())!);
    return data;
  }

  group('TapeBackdrop', () {
    testWidgets(
      'is void at the corners and a little lighter in the middle: the vignette',
      (tester) async {
        setWindow(tester, const Size(640, 360));
        await tester.pumpWidget(
          tapeHarness(kit: kit, child: const TapeBackdrop()),
        );
        final data = await pixelsOf(tester);
        const w = 1280;

        int luminance(int x, int y) {
          final p = data.getUint32((y * w + x) * 4);
          return ((p >> 24) & 0xFF) + ((p >> 16) & 0xFF) + ((p >> 8) & 0xFF);
        }

        // Average a block, so that the grain does not decide it.
        int block(int cx, int cy) {
          var total = 0;
          for (var y = cy - 8; y < cy + 8; y++) {
            for (var x = cx - 8; x < cx + 8; x++) {
              total += luminance(x, y);
            }
          }
          return total ~/ 256;
        }

        final centre = block(640, 360);
        final corner = block(12, 12);

        expect(
          centre,
          greaterThan(corner),
          reason: 'carbon.900 in the middle, void at the edges',
        );
        // void is 5+6+7 = 18; carbon.900 is 11+13+16 = 40.
        expect(corner, inInclusiveRange(16, 28));
        expect(centre, inInclusiveRange(30, 46));
      },
    );

    testWidgets('has grain: the corner is not one flat colour', (tester) async {
      setWindow(tester, const Size(640, 360));
      await tester.pumpWidget(
        tapeHarness(kit: kit, child: const TapeBackdrop()),
      );
      final data = await pixelsOf(tester);
      final values = <int>{};
      for (var y = 0; y < 40; y++) {
        for (var x = 0; x < 40; x++) {
          values.add(data.getUint32((y * 1280 + x) * 4));
        }
      }

      expect(values.length, greaterThan(3));
    });

    testWidgets('is never lighter than a hint: it stays a dark canvas', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      await tester.pumpWidget(
        tapeHarness(kit: kit, child: const TapeBackdrop()),
      );
      final data = await pixelsOf(tester);
      var brightest = 0;
      for (var i = 0; i < 1280 * 720; i++) {
        final p = data.getUint32(i * 4);
        brightest = [
          brightest,
          (p >> 24) & 0xFF,
          (p >> 16) & 0xFF,
          (p >> 8) & 0xFF,
        ].reduce((a, b) => a > b ? a : b);
      }

      expect(brightest, lessThan(40));
    });

    testWidgets('VFD adds its mesh, and the others do not', (tester) async {
      setWindow(tester, const Size(640, 360));

      Future<Set<int>> distinctIn(Livery livery) async {
        await tester.pumpWidget(
          tapeHarness(
            kit: kit,
            theme: TapeThemeData(livery: livery),
            child: const TapeBackdrop(),
          ),
        );
        final data = await pixelsOf(tester);
        return {
          for (var y = 0; y < 60; y++)
            for (var x = 0; x < 60; x++) data.getUint32((y * 1280 + x) * 4),
        };
      }

      final ion = await distinctIn(Liveries.ion);
      final vfd = await distinctIn(Liveries.vfd);

      expect(
        vfd.length,
        greaterThan(ion.length),
        reason: 'hairlines and grain, against grain alone',
      );
    });

    testWidgets('draws its child over the canvas', (tester) async {
      setWindow(tester, const Size(640, 360));
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          child: const TapeBackdrop(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 20,
                height: 20,
                child: ColoredBox(color: Color(0xFFFF0000)),
              ),
            ),
          ),
        ),
      );
      final data = await pixelsOf(tester);

      expect(data.getUint32(0), 0xFF0000FF);
    });
  });

  group('StaticLayer', () {
    testWidgets('records its picture once and replays it', (tester) async {
      setWindow(tester, const Size(640, 360));
      var painted = 0;
      Widget layer(Object key) => tapeHarness(
        kit: kit,
        child: StaticLayer(cacheKey: key, paint: (canvas, size) => painted++),
      );

      await tester.pumpWidget(layer('a'));
      await tester.pumpWidget(layer('a'));
      await tester.pump();

      expect(painted, 1);
    });

    testWidgets('records again when the key changes', (tester) async {
      setWindow(tester, const Size(640, 360));
      var painted = 0;
      Widget layer(Object key) => tapeHarness(
        kit: kit,
        child: StaticLayer(cacheKey: key, paint: (canvas, size) => painted++),
      );

      await tester.pumpWidget(layer('a'));
      await tester.pumpWidget(layer('b'));
      await tester.pumpWidget(layer('b'));

      expect(painted, 2);
    });

    testWidgets('records again when the size changes', (tester) async {
      var painted = 0;
      Widget layer() => tapeHarness(
        kit: kit,
        child: StaticLayer(cacheKey: 'a', paint: (canvas, size) => painted++),
      );
      setWindow(tester, const Size(640, 360));
      await tester.pumpWidget(layer());
      setWindow(tester, const Size(800, 360));
      await tester.pumpWidget(layer());
      await tester.pump();

      expect(painted, 2);
    });

    testWidgets('does not repaint when something else on screen does', (
      tester,
    ) async {
      setWindow(tester, const Size(640, 360));
      var painted = 0;
      final tick = ValueNotifier<int>(0);
      addTearDown(tick.dispose);

      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          child: Stack(
            children: [
              StaticLayer(cacheKey: 'a', paint: (canvas, size) => painted++),
              RepaintBoundary(
                child: CustomPaint(
                  painter: _Ticker(tick),
                  size: const Size(50, 50),
                ),
              ),
            ],
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        tick.value++;
        await tester.pump();
      }

      expect(painted, 1);
    });

    testWidgets('draws what it recorded', (tester) async {
      setWindow(tester, const Size(640, 360));
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          child: StaticLayer(
            cacheKey: 'a',
            paint: (canvas, size) => canvas.drawRect(
              const Rect.fromLTWH(0, 0, 10, 10),
              Paint()..color = const Color(0xFF00FF00),
            ),
          ),
        ),
      );
      final data = await pixelsOf(tester);

      expect(data.getUint32(0), 0x00FF00FF);
    });
  });

  group('MotionScope', () {
    testWidgets(
      'gives the clock to the widgets below it, and its own vsync clock by default',
      (tester) async {
        MotionClock? seen;
        await tester.pumpWidget(
          MotionScope(
            child: Builder(
              builder: (context) {
                seen = MotionScope.of(context);
                return const SizedBox();
              },
            ),
          ),
        );

        expect(seen, isA<VsyncMotionClock>());
      },
    );

    testWidgets('a clock given to it is not disposed by it', (tester) async {
      final clock = ManualMotionClock();
      addTearDown(clock.dispose);
      MotionClock? seen;

      await tester.pumpWidget(
        MotionScope.value(
          clock: clock,
          child: Builder(
            builder: (context) {
              seen = MotionScope.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(const SizedBox());

      expect(seen, same(clock));
      expect(clock.attachedCount, 0);
    });

    testWidgets('an app-owned clock is disposed with the scope', (
      tester,
    ) async {
      await tester.pumpWidget(const MotionScope(child: SizedBox()));

      await tester.pumpWidget(const SizedBox());

      // Nothing is left ticking, or the test would fail its ticker check.
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('maybeOf is null with no scope', (tester) async {
      MotionClock? seen = ManualMotionClock();
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = MotionScope.maybeOf(context);
            return const SizedBox();
          },
        ),
      );

      expect(seen, isNull);
    });
  });
}

class _Ticker extends CustomPainter {
  _Ticker(this.tick) : super(repaint: tick);

  final ValueNotifier<int> tick;

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(_Ticker old) => false;
}
