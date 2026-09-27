import 'package:flutter/widgets.dart';

import '../ui/design/components/backdrop.dart';
import '../ui/design/components/controls/tape_button.dart';
import '../ui/design/icons/icons.dart';
import '../ui/design/motion/motion_scope.dart';
import '../ui/design/render/render_kit.dart';
import '../ui/design/theme/tape_theme.dart';
import '../ui/design/tokens/colors.dart';
import '../ui/design/tokens/livery.dart';
import '../ui/design/tokens/spacing.dart';
import '../ui/dev/dev_settings.dart';
import '../ui/lab/design_lab.dart';

/// Root widget.
///
/// The Strip and its pages arrive in phase 3b (CLAUDE.md 13); until then this is
/// the `void` canvas the launch theme matches, with one way into the design
/// system: a small dev button that opens the Design Lab (DESIGN.md 13.2), shown
/// in debug and profile builds, and in a release build made with
/// `--dart-define=TAPEDASH_DEV=true`. It uses [WidgetsApp] rather than
/// `MaterialApp`, since Material widgets are banned (DESIGN.md 13.1).
class TapeDashApp extends StatelessWidget {
  const TapeDashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: TapeColors.voidColor,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => const _Shell(),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  late final TapeRenderKit _kit = TapeRenderKit();
  bool _labOpen = false;

  @override
  void initState() {
    super.initState();
    if (DevMode.launchScreen == 'lab') _labOpen = true;
  }

  @override
  void dispose() {
    _kit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MotionScope(
      child: TapeRenderScope(
        kit: _kit,
        child: TapeTheme(
          data: TapeThemeData(livery: Liveries.ion),
          child: _labOpen
              ? DesignLab(onClose: () => setState(() => _labOpen = false))
              : TapeBackdrop(
                  child: Stack(
                    children: [
                      if (DevMode.buttonVisible)
                        Positioned(
                          right: TapeSpace.s4,
                          bottom: TapeSpace.s4,
                          child: TapeButton(
                            label: 'Design Lab',
                            icon: TapeIcon.hud,
                            onPressed: () => setState(() => _labOpen = true),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
