import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/motion_scope.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/render/tape_fonts.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/colors.dart';

/// Loads the real fonts, so that what a test draws is in the real typography
/// (DESIGN.md 14.1). Call it in `setUpAll`.
Future<void> loadTapeFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await TapeFonts.load();
}

/// Where captures are written: `TAPEDASH_CAPTURE_DIR`, or a temporary directory.
Directory captureDirectory() {
  final path = Platform.environment['TAPEDASH_CAPTURE_DIR'];
  final dir = path != null && path.isNotEmpty
      ? Directory(path)
      : Directory('${Directory.systemTemp.path}/tapedash_captures');
  dir.createSync(recursive: true);
  return dir;
}

/// Wraps [child] the way the app does: an app shell for the media query, the
/// design theme, the render kit, and the `void` canvas behind everything.
///
/// [motion] is the clock the components run on: a manual one by default, which
/// the test steps.
Widget tapeHarness({
  required Widget child,
  required TapeRenderKit kit,
  TapeThemeData? theme,
  MotionClock? motion,
}) {
  final clock = motion ?? ManualMotionClock();
  if (motion == null) addTearDown(clock.dispose);
  return WidgetsApp(
    color: TapeColors.voidColor,
    debugShowCheckedModeBanner: false,
    builder: (context, _) => MotionScope.value(
      clock: clock,
      child: TapeRenderScope(
        kit: kit,
        child: TapeTheme(
          data: theme ?? TapeThemeData(),
          child: RepaintBoundary(
            child: ColoredBox(color: TapeColors.voidColor, child: child),
          ),
        ),
      ),
    ),
  );
}

/// Sets the test window to [logical] logical pixels at [dpr].
void setWindow(WidgetTester tester, Size logical, {double dpr = 2}) {
  tester.view.physicalSize = logical * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
}

/// Renders whatever is on screen to a PNG at [name] in the capture directory, and
/// returns its bytes.
Future<List<int>> capturePng(
  WidgetTester tester,
  String name, {
  double? pixelRatio,
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  late List<int> bytes;
  await tester.runAsync(() async {
    final image = await boundary.toImage(
      pixelRatio: pixelRatio ?? tester.view.devicePixelRatio,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    bytes = data!.buffer.asUint8List();
    File('${captureDirectory().path}/$name.png').writeAsBytesSync(bytes);
    image.dispose();
  });
  return bytes;
}

/// The raw RGBA pixels of whatever is on screen.
Future<ui.Image> renderImage(WidgetTester tester, {double? pixelRatio}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  late ui.Image image;
  await tester.runAsync(() async {
    image = await boundary.toImage(
      pixelRatio: pixelRatio ?? tester.view.devicePixelRatio,
    );
  });
  return image;
}
