// The Design Lab (DESIGN.md 13.2): the gallery, its switchers actually take
// effect, and capture-all writes real files.

import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/components/rolling_numerals.dart';
import 'package:tapedash/ui/design/components/seven_segment_numerals.dart';
import 'package:tapedash/ui/design/motion/motion_scope.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/colors.dart';
import 'package:tapedash/ui/lab/design_lab.dart';

import '../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  Future<void> pump(
    WidgetTester tester, {
    CaptureSink? sink,
    VoidCallback? onClose,
    Future<Uint8List?> Function(GlobalKey key)? captureRenderer,
  }) async {
    setWindow(tester, const Size(640, 360));
    final kit = TapeRenderKit();
    addTearDown(kit.dispose);
    // The Lab manages its own TapeTheme (the switchers change it), so this
    // harness gives it only what a screen at the top of the app would find:
    // the render kit and a motion clock, by the same route WidgetsApp gives
    // them in lib/app/app.dart.
    await tester.pumpWidget(
      WidgetsApp(
        color: TapeColors.voidColor,
        builder: (context, _) => MotionScope(
          child: TapeRenderScope(
            kit: kit,
            child: DesignLab(
              captureSink: sink,
              captureRenderer: captureRenderer,
              onClose: onClose,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Taps whichever button or segmented cell shows [text] (the Lab uppercases
  /// every button and cell label). The bottom bar scrolls horizontally, as it
  /// does on the small screens it is built for, so this scrolls the target
  /// into view first.
  Future<void> tapLabel(WidgetTester tester, String text) async {
    final target = find.text(text.toUpperCase()).first;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
  }

  testWidgets(
    'shows the numerals tab first, with a live value and a money readout',
    (tester) async {
      await pump(tester);

      expect(find.byType(SairaNumerals), findsNWidgets(2));
    },
  );

  testWidgets('the CONTROLS and ICONS tabs switch the gallery', (tester) async {
    await pump(tester);

    await tapLabel(tester, 'controls');
    await tester.pump();
    expect(find.text('BUTTONS'), findsOneWidget);

    await tapLabel(tester, 'icons');
    await tester.pump();
    expect(find.text('adapter'), findsOneWidget);
  });

  testWidgets('the livery switcher changes what VFD-only numerals are shown', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(SevenSegmentNumerals), findsNothing);

    await tapLabel(tester, 'vfd');
    await tester.pump();

    expect(find.byType(SevenSegmentNumerals), findsNWidgets(2));
  });

  testWidgets(
    'the frame switcher letterboxes the gallery to the chosen ratio',
    (tester) async {
      await pump(tester);
      // The capture area is the RepaintBoundary that wraps the gallery content:
      // its nearest RepaintBoundary ancestor.
      Size captureSize() => tester.getSize(
        find
            .ancestor(
              of: find.byType(SairaNumerals).first,
              matching: find.byType(RepaintBoundary),
            )
            .first,
      );
      final native = captureSize();

      await tapLabel(tester, '20:9');
      await tester.pump();
      final framed = captureSize();

      expect(framed.width, lessThan(native.width));
      expect(framed.width / framed.height, closeTo(20 / 9, 0.01));
    },
  );

  testWidgets('reduce motion is threaded into the theme', (tester) async {
    await pump(tester);
    // The toggle beside the REDUCE MOTION label, found by walking up to their
    // shared row and back down to the one interactive control in it.
    final row = find
        .ancestor(of: find.text('REDUCE MOTION'), matching: find.byType(Row))
        .first;
    final toggle = find
        .descendant(of: row, matching: find.byType(GestureDetector))
        .first;
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();

    await tester.tap(toggle);
    await tester.pump();

    final theme = TapeTheme.of(
      tester.element(find.byType(RollingNumerals).first),
    );
    expect(theme.reduceMotion, isTrue);
  });

  testWidgets(
    'capture-all renders every tab x livery x mode, and writes each once',
    (tester) async {
      final written = <String>[];
      var allNonEmpty = true;
      // A fake renderer: this proves the sweep's own logic (every combination,
      // once each, the right names, the button disabled meanwhile), without
      // driving the real RenderRepaintBoundary.toImage through repeated frame
      // pumps inside one tester.runAsync block, which does not settle under
      // flutter_test (see the "renders real pixels" test below, which drives
      // the real renderer the way it is safe to: no pumps in the same
      // runAsync call).
      await pump(
        tester,
        sink: (name, bytes) async {
          // Not expect() here: it is called from inside _captureAll's own
          // await chain, which trips flutter_test's guard against two guarded
          // calls racing. Checked once, after the sweep, below instead.
          written.add(name);
          allNonEmpty &= bytes.isNotEmpty;
        },
        captureRenderer: (key) async => Uint8List.fromList([1, 2, 3]),
      );

      // Invoked directly rather than through a simulated tap: the button sits
      // off the small screen until the bottom bar is scrolled, and other tests
      // in this file already exercise a real tap on a button in this same bar.
      final button = tester.widget<TapeButton>(
        find.byWidgetPredicate(
          (w) => w is TapeButton && w.label == 'Capture all',
        ),
      );
      button.onPressed!();
      await tester.pump();
      expect(
        tester
            .widget<TapeButton>(
              find.byWidgetPredicate(
                (w) => w is TapeButton && w.label == 'Capturing…',
              ),
            )
            .onPressed,
        isNull,
        reason: 'disabled while it runs',
      );
      for (var i = 0; i < 400 && written.length < 36; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // A couple more frames for the final status text and the button
      // re-enabling, which are set after the last capture completes.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      expect(written.length, 36, reason: '3 tabs x 4 liveries x 3 modes');
      expect(written.toSet().length, 36, reason: 'no name is written twice');
      expect(allNonEmpty, isTrue);
      expect(find.text('Wrote 36 captures'), findsOneWidget);
    },
  );

  testWidgets(
    'DesignLab.renderKeyToPng, the sweep\'s real renderer, produces a real PNG',
    (tester) async {
      // Tested on its own, on an already-settled tree: no pump() shares the
      // runAsync block the real toImage() needs, which is the combination the
      // test above found does not settle under flutter_test.
      final key = GlobalKey();
      setWindow(tester, const Size(64, 64));
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: const ColoredBox(color: Color(0xFF123456)),
        ),
      );

      Uint8List? png;
      await tester.runAsync(() async {
        png = await DesignLab.renderKeyToPng(key);
      });

      expect(png, isNotNull);
      // A PNG file starts with this 4-byte signature.
      expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    },
  );

  testWidgets('closing calls onClose', (tester) async {
    var closed = false;
    await pump(tester, onClose: () => closed = true);

    await tapLabel(tester, 'close');

    expect(closed, isTrue);
  });
}
