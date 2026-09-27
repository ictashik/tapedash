// Ad-hoc capture of the icon set. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/icons/icons.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';

import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  testWidgets('icons', (tester) async {
    setWindow(tester, const Size(640, 360));
    final kit = TapeRenderKit();
    addTearDown(kit.dispose);
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        theme: TapeThemeData(livery: Liveries.ion),
        child: Center(
          child: Wrap(
            spacing: 20,
            runSpacing: 20,
            alignment: WrapAlignment.center,
            children: [
              for (final icon in TapeIcon.values)
                SizedBox(
                  width: 56,
                  child: Column(
                    children: [
                      TapeIconView(
                        icon,
                        size: 44,
                        color: Liveries.ion.accentCore,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        icon.label,
                        style: const TextStyle(
                          fontSize: 8,
                          color: Color(0xFF7A838F),
                          fontFamily: 'BarlowSemiCondensed',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await capturePng(tester, 'icons');
  }, skip: !enabled);
}
