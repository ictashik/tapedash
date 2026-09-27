// The real app on an emulator or a phone: CLAUDE.md 10, layer 5.
//
//   flutter test integration_test/app_launch_test.dart -d <device>

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tapedash/main.dart' as app;
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/tokens/colors.dart';
import 'package:tapedash/ui/lab/design_lab.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('starts in landscape on the void canvas', (tester) async {
    await app.main();
    await tester.pumpAndSettle();

    final size = tester.view.physicalSize;
    expect(size.width, greaterThan(size.height), reason: 'landscape only');
    expect(find.byType(TapeBackdrop), findsOneWidget);

    // Grain (DESIGN.md 4.10) varies each pixel around the token colour, so a
    // block is averaged rather than one pixel read exactly.
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = (await image.toByteData())!;
    var r = 0, g = 0, b = 0;
    const side = 24;
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final p = data.getUint32((y * image.width + x) * 4);
        r += (p >> 24) & 0xFF;
        g += (p >> 16) & 0xFF;
        b += (p >> 8) & 0xFF;
      }
    }
    const n = side * side;
    image.dispose();
    expect(r / n, closeTo(TapeColors.voidColor.r * 255, 4));
    expect(g / n, closeTo(TapeColors.voidColor.g * 255, 4));
    expect(b / n, closeTo(TapeColors.voidColor.b * 255, 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dev button opens the Design Lab and cycles its tabs', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TapeButton, 'DESIGN LAB'));
    await tester.pumpAndSettle();
    expect(find.byType(DesignLab), findsOneWidget);

    for (final label in ['CONTROLS', 'ICONS', 'NUMERALS']) {
      await tester.tap(find.widgetWithText(TapeButton, label));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull, reason: label);
    }

    await tester.tap(find.widgetWithText(TapeButton, 'CLOSE'));
    await tester.pumpAndSettle();
    expect(find.byType(DesignLab), findsNothing);
  });
}
