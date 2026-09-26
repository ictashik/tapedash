import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app.dart';
import 'package:tapedash/ui/design/tokens/colors.dart';

void main() {
  testWidgets('boots to a void canvas with no exceptions', (tester) async {
    await tester.pumpWidget(const TapeDashApp());

    final canvas = tester.widget<ColoredBox>(find.byType(ColoredBox));
    expect(canvas.color, TapeColors.voidColor);
    expect(tester.takeException(), isNull);
  });
}
