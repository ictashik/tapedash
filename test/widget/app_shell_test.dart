// The app boots onto the void canvas with no exceptions, and the dev button
// opens and closes the Design Lab (DESIGN.md 13.2). The Strip and its pages
// arrive in phase 3b (CLAUDE.md 13); this is what there is to boot onto so far.
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/tokens/colors.dart';
import 'package:tapedash/ui/lab/design_lab.dart';

/// Sets the test surface to a landscape phone size, as DESIGN.md 14.1 checks at.
void _setPhoneWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

/// The average colour of the top-left corner. Grain (DESIGN.md 4.10) varies each
/// pixel around the token colour, so a block is averaged rather than reading one.
Future<Color> _cornerColour(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  late ByteData data;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData();
    data = bytes!;
    image.dispose();
  });
  var r = 0, g = 0, b = 0;
  const side = 24;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      final p = data.getUint32((y * 1280 + x) * 4);
      r += (p >> 24) & 0xFF;
      g += (p >> 16) & 0xFF;
      b += (p >> 8) & 0xFF;
    }
  }
  const n = side * side;
  return Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
}

void main() {
  testWidgets('boots to the void canvas with no exceptions', (tester) async {
    _setPhoneWindow(tester);
    await tester.pumpWidget(const TapeDashApp());
    await tester.pump();

    expect(find.byType(TapeBackdrop), findsOneWidget);
    final corner = await _cornerColour(tester);
    expect(corner.r * 255, closeTo(TapeColors.voidColor.r * 255, 4));
    expect(corner.g * 255, closeTo(TapeColors.voidColor.g * 255, 4));
    expect(corner.b * 255, closeTo(TapeColors.voidColor.b * 255, 4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dev button opens the Design Lab, and Close returns', (
    tester,
  ) async {
    _setPhoneWindow(tester);
    await tester.pumpWidget(const TapeDashApp());
    await tester.pump();
    expect(find.byType(DesignLab), findsNothing);

    await tester.tap(find.widgetWithText(TapeButton, 'DESIGN LAB'));
    await tester.pump();
    expect(find.byType(DesignLab), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(TapeButton, 'CLOSE'));
    await tester.pump();
    expect(find.byType(DesignLab), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
