// The app shell in Demo Mode: parked at the start, then moving. Skipped unless
// TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app.dart';
import 'package:tapedash/core/fake_clock.dart';

import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  testWidgets('demo drive: parked, moving', (tester) async {
    setWindow(tester, const Size(640, 360));
    final clock = FakeClock()..advance(const Duration(seconds: 100));
    await tester.pumpWidget(
      RepaintBoundary(
        child: TapeDashApp(clock: clock, scheduler: clock),
      ),
    );
    Future<void> run(int seconds) async {
      for (var i = 0; i < seconds * 10; i++) {
        clock.advance(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await run(12);
    await capturePng(tester, 'shell-early');
    await run(60);
    await capturePng(tester, 'shell-later');
  }, skip: !enabled);
}
