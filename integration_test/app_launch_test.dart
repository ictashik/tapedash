// The real app on an emulator or a phone: CLAUDE.md 10, layer 5.
//
//   flutter test integration_test/app_launch_test.dart -d <device>
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tapedash/main.dart' as app;
import 'package:tapedash/ui/design/tokens/colors.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('starts in landscape on the void canvas', (tester) async {
    await app.main();
    await tester.pumpAndSettle();

    final size = tester.view.physicalSize;
    expect(size.width, greaterThan(size.height), reason: 'landscape only');
    expect(
      tester.widget<ColoredBox>(find.byType(ColoredBox)).color,
      TapeColors.voidColor,
    );
    expect(tester.takeException(), isNull);
  });
}
