// A first look at the status strip. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/components/status_strip.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';

import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  Future<void> shot(
    WidgetTester tester,
    String name,
    Widget Function() build,
  ) async {
    setWindow(tester, const Size(520, 90));
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: TapeBackdrop(child: Center(child: build())),
      ),
    );
    await tester.pump();
    await capturePng(tester, name);
    motion.dispose();
    kit.dispose();
  }

  testWidgets('left flank, motion: linked and lost', (tester) async {
    await shot(
      tester,
      'status-left-linked',
      () => StatusStripLeft(
        adapter: ValueNotifier(AdapterLinkState.flowing),
        gpsHasFix: ValueNotifier(true),
        parkedShare: ValueNotifier(0),
      ),
    );
    await shot(
      tester,
      'status-left-searching',
      () => StatusStripLeft(
        adapter: ValueNotifier(AdapterLinkState.searching),
        gpsHasFix: ValueNotifier(false),
        parkedShare: ValueNotifier(0),
      ),
    );
    await shot(
      tester,
      'status-left-lost-parked',
      () => StatusStripLeft(
        adapter: ValueNotifier(AdapterLinkState.lost),
        gpsHasFix: ValueNotifier(false),
        parkedShare: ValueNotifier(1),
      ),
    );
  }, skip: !enabled);

  testWidgets('right flank: clock, phone hot', (tester) async {
    await shot(
      tester,
      'status-right-plain',
      () => StatusStripRight(
        time: ValueNotifier(DateTime(2026, 1, 1, 14, 7)),
        use24Hour: true,
        phoneHot: ValueNotifier(false),
        parkedShare: ValueNotifier(0),
      ),
    );
    await shot(
      tester,
      'status-right-hot-parked',
      () => StatusStripRight(
        time: ValueNotifier(DateTime(2026, 1, 1, 14, 7)),
        use24Hour: false,
        phoneHot: ValueNotifier(true),
        parkedShare: ValueNotifier(1),
      ),
    );
  }, skip: !enabled);
}
