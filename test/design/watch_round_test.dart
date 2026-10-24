// The round face (DESIGN.md 16.3, 16.10): nothing is drawn outside the circle
// (the corners of a round screen are not there), and every line of text sits where
// the circle is wide enough for it. Every face, at every size the watch is checked
// at, in every livery for the Drive face.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/watch/watch_face.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/palette.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/watch.dart';
import 'package:tapedash/ui/pages/watch/watch_reel.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../support/sim_shell.dart';
import 'support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  Future<void> run(
    WidgetTester tester,
    ManualMotionClock motion,
    FakeClock clock,
    double seconds,
  ) async {
    for (var i = 0; i < seconds * 60; i++) {
      motion.tick(1 / 60);
      clock.advance(const Duration(microseconds: 16667));
      if (i % 20 == 0) await tester.pump();
    }
    await tester.pump();
  }

  /// The brightest channel of any pixel more than [slack] lp outside the circle.
  Future<int> brightestOutside(WidgetTester tester, double d) async {
    final image = await renderImage(tester);
    late ByteData data;
    await tester.runAsync(
      () async =>
          data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!,
    );
    final dpr = tester.view.devicePixelRatio;
    final c = image.width / 2;
    // A line of anti-aliasing at the edge is not a corner: 1 lp of slack.
    final limit = (d / 2 + 1) * dpr;
    var brightest = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final dx = x + 0.5 - c;
        final dy = y + 0.5 - c;
        if (dx * dx + dy * dy <= limit * limit) continue;
        final i = (y * image.width + x) * 4;
        for (var k = 0; k < 3; k++) {
          if (data.getUint8(i + k) > brightest) {
            brightest = data.getUint8(i + k);
          }
        }
      }
    }
    image.dispose();
    return brightest;
  }

  /// Every `Text` on screen as a left-middle and a right-middle point, which must
  /// both lie inside the rim's inner edge: a line never runs over the ring.
  void expectTextInsideRim(WidgetTester tester, double d, String where) {
    final face = WatchFace(d);
    final inner = face.rimInner + 2;
    for (final e in find.byType(Text).evaluate()) {
      final box = e.renderObject! as RenderBox;
      if (!box.attached || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      for (final p in [rect.centerLeft, rect.centerRight]) {
        expect(
          (p - face.centre).distance,
          lessThanOrEqualTo(inner),
          reason:
              '$where: "${(e.widget as Text).data}" at $rect leaves the rim '
              'at $d',
        );
      }
    }
  }

  const sizes = [192.0, 198.0, 225.0, 240.0, 280.0];

  for (final d in sizes) {
    testWidgets('every face is inside the circle at $d lp', (tester) async {
      setWindow(tester, Size(d, d));
      final kit = TapeRenderKit();
      final motion = ManualMotionClock();
      final clock = FakeClock();
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(
            livery: Liveries.ion.withNumeralWeightAtLeast(
              TapeWatch.minNumeralWeight,
            ),
          ),
          child: SimWatchShell(
            clock: clock,
            scheduler: clock,
            scenario: 'city_stop_go',
          ),
        ),
      );
      final shell = tester.state<SimWatchShellState>(
        find.byType(SimWatchShell),
      );
      final reel = tester.state<WatchReelState>(find.byType(WatchReel));

      for (var s = 0; s < 400; s++) {
        await run(tester, motion, clock, 1);
        if ((shell.drive.vehicle.speed.value?.value ?? 0) > 40) break;
      }
      expect(await brightestOutside(tester, d), lessThan(16), reason: 'drive');
      expectTextInsideRim(tester, d, 'drive');

      reel.goTo(1);
      await run(tester, motion, clock, 2);
      expect(await brightestOutside(tester, d), lessThan(16), reason: 'money');
      expectTextInsideRim(tester, d, 'money');

      // The car stops, and the other faces open.
      reel.goTo(0);
      for (var s = 0; s < 600; s++) {
        await run(tester, motion, clock, 1);
        if (shell.drive.vehicle.mode.value == DrivingMode.parked) break;
      }
      await run(tester, motion, clock, 3);
      expect(
        await brightestOutside(tester, d),
        lessThan(16),
        reason: 'drive, parked',
      );
      expectTextInsideRim(tester, d, 'drive, parked');
      for (final (i, name) in [
        (1, 'money, parked'),
        (2, 'where'),
        (3, 'menu'),
      ]) {
        reel.goTo(i);
        await run(tester, motion, clock, 2);
        expect(await brightestOutside(tester, d), lessThan(16), reason: name);
        expectTextInsideRim(tester, d, name);
      }

      // The wheel is over the faces, and its rows run off the circle on purpose:
      // what it draws is clipped by the face, and its centre row is inside.
      await tester.tapAt(Offset(d / 2, d / 2));
      await run(tester, motion, clock, 1);
      expect(await brightestOutside(tester, d), lessThan(16), reason: 'wheel');
      kit.dispose();
      motion.dispose();
    });
  }

  for (final livery in Liveries.all) {
    for (final mode in TapeMode.values) {
      testWidgets('the Drive face is inside the circle in ${livery.name}, '
          '${mode.label}', (tester) async {
        const d = 225.0;
        setWindow(tester, const Size(d, d));
        final kit = TapeRenderKit();
        final motion = ManualMotionClock();
        final clock = FakeClock();
        await tester.pumpWidget(
          tapeHarness(
            kit: kit,
            motion: motion,
            theme: TapeThemeData(
              livery: livery.withNumeralWeightAtLeast(
                TapeWatch.minNumeralWeight,
              ),
              mode: mode,
            ),
            child: SimWatchShell(
              clock: clock,
              scheduler: clock,
              scenario: 'highway_cruise',
            ),
          ),
        );
        await run(tester, motion, clock, 25);
        expect(await brightestOutside(tester, d), lessThan(16));
        kit.dispose();
        motion.dispose();
      });
    }
  }

  testWidgets('and the check can fail: a lit corner is found', (tester) async {
    setWindow(tester, const Size(225, 225));
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: const Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 20,
            height: 20,
            child: ColoredBox(color: Color(0xFFFFFFFF)),
          ),
        ),
      ),
    );
    expect(await brightestOutside(tester, 225), 255);
    kit.dispose();
    motion.dispose();
  });
}
