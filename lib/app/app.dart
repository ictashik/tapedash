import 'package:flutter/widgets.dart';

import '../core/clock.dart';
import '../core/scheduler.dart';
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
import 'drive_shell.dart';

/// Root widget.
///
/// The app opens straight onto the Strip, driven by Demo Mode (onboarding, which
/// chooses between the demo and a real car, is a later piece of phase 3b), with
/// one way into the design system: a small dev button that opens the Design Lab (DESIGN.md 13.2), shown
/// in debug and profile builds, and in a release build made with
/// `--dart-define=TAPEDASH_DEV=true`. It uses [WidgetsApp] rather than
/// `MaterialApp`, since Material widgets are banned (DESIGN.md 13.1).
class TapeDashApp extends StatelessWidget {
  const TapeDashApp({
    super.key,
    this.clock = const SystemClock(),
    this.scheduler = const SystemScheduler(),
  });

  /// Time, injected (CLAUDE.md 5): a test gives a `FakeClock` for both.
  final Clock clock;
  final Scheduler scheduler;

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: TapeColors.voidColor,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => _Shell(clock: clock, scheduler: scheduler),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell({required this.clock, required this.scheduler});

  final Clock clock;
  final Scheduler scheduler;

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
              : ColoredBox(
                  color: TapeColors.voidColor,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: DriveShell(
                          clock: widget.clock,
                          scheduler: widget.scheduler,
                        ),
                      ),
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
