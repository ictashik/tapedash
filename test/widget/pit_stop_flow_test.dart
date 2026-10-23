// Pit Stop through the whole shell: from the dock, while parked, a fill-up is
// typed and saved, and the price it makes is the one the next visit shows.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/pages/pitstop/pit_stop_page.dart';

import '../design/support/harness.dart';
import '../support/sim_shell.dart';

void main() {
  setUpAll(loadTapeFonts);

  testWidgets(
    'parked, the dock opens Pit Stop; a saved fill-up sets the price',
    (tester) async {
      setWindow(tester, const Size(720, 360));
      final kit = TapeRenderKit();
      addTearDown(kit.dispose);
      final motion = ManualMotionClock();
      addTearDown(motion.dispose);
      final clock = FakeClock()..advance(const Duration(seconds: 100));
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          child: SimDriveShell(
            clock: clock,
            scheduler: clock,
            scenario: 'cold_start_idle',
          ),
        ),
      );
      Future<void> run(int ms) async {
        for (var t = 0; t < ms; t += 50) {
          motion.tick(0.05);
          clock.advance(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      // Idling with the engine on: parked after five seconds of standing still.
      await run(30000);
      expect(find.byType(PitStopPage), findsNothing);
      await tester.tap(find.widgetWithText(TapeButton, 'PIT STOP'));
      await run(300);
      expect(find.byType(PitStopPage), findsOneWidget);

      Future<void> type(String keys) async {
        for (final k in keys.split('')) {
          await tester.tap(find.text(k).first);
          await tester.pump();
        }
      }

      await type('20');
      await tester.tap(find.text('AMOUNT PAID'));
      await tester.pump();
      await type('2100');
      await tester.tap(find.widgetWithText(TapeButton, 'SAVE'));
      await run(300);
      // The column fills and collapses, then the page closes: 900 ms.
      await run(1500);
      expect(find.byType(PitStopPage), findsNothing);

      // The price it made is the one the form shows next time.
      await tester.tap(find.widgetWithText(TapeButton, 'PIT STOP'));
      await run(300);
      expect(find.text('Now ₹105.00 a litre'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
