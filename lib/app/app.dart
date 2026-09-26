import 'package:flutter/widgets.dart';

import '../ui/design/tokens/colors.dart';

/// Root widget.
///
/// For now this is only the `void` canvas. The cockpit arrives with the design
/// system and the Strip (DESIGN.md 7.1). It uses [WidgetsApp] rather than
/// `MaterialApp`, since Material widgets are banned (DESIGN.md 13.1).
class TapeDashApp extends StatelessWidget {
  const TapeDashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: TapeColors.voidColor,
      builder: (context, child) =>
          const ColoredBox(color: TapeColors.voidColor),
    );
  }
}
