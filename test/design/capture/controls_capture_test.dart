// A sheet of the parked controls. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/components/controls/tape_list_row.dart';
import 'package:tapedash/ui/design/components/controls/tape_segmented.dart';
import 'package:tapedash/ui/design/components/controls/tape_slider.dart';
import 'package:tapedash/ui/design/components/controls/tape_toggle.dart';
import 'package:tapedash/ui/design/components/tape_label.dart';
import 'package:tapedash/ui/design/icons/icons.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';

import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  for (final livery in [Liveries.ion, Liveries.ember]) {
    testWidgets('controls ${livery.name}', (tester) async {
      setWindow(tester, const Size(640, 360));
      final kit = TapeRenderKit();
      addTearDown(kit.dispose);
      final motion = ManualMotionClock();
      addTearDown(motion.dispose);

      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: livery),
          child: TapeBackdrop(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const TapeLabel('Buttons'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            TapeButton(
                              label: 'Garage',
                              icon: TapeIcon.garage,
                              onPressed: () {},
                            ),
                            TapeButton(
                              label: 'Save',
                              primary: true,
                              onPressed: () {},
                            ),
                            TapeButton(
                              label: 'Set fuel price',
                              tone: ButtonTone.money,
                              onPressed: () {},
                            ),
                            const TapeButton(label: 'Disabled'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const TapeLabel('Toggle and selector'),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            TapeToggle(value: true, onChanged: (_) {}),
                            TapeToggle(value: false, onChanged: (_) {}),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TapeSegmented<String>(
                                segments: const [
                                  TapeSegment('a', 'Gentle'),
                                  TapeSegment('b', 'Normal'),
                                  TapeSegment('c', 'Sporty'),
                                ],
                                value: 'b',
                                onChanged: (_) {},
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TapeSlider(
                          label: 'Halo',
                          value: 0.3,
                          onChanged: (_) {},
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 240,
                    child: Column(
                      children: [
                        TapeListRow(
                          label: 'Fuel price',
                          value: '₹104.2 / L',
                          icon: TapeIcon.pitStop,
                          onTap: () {},
                        ),
                        TapeListRow(
                          label: 'Livery',
                          value: livery.name,
                          icon: TapeIcon.hud,
                          onTap: () {},
                        ),
                        const TapeListRow(label: 'Version', value: '0.2.0'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      motion.advance(const Duration(seconds: 1));
      await tester.pump();
      await capturePng(tester, 'controls-${livery.name.toLowerCase()}');
    }, skip: !enabled);
  }
}
