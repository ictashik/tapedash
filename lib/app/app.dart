import 'package:flutter/widgets.dart';

import '../core/clock.dart';
import '../core/scheduler.dart';
import '../ui/design/components/backdrop.dart';
import '../ui/design/components/controls/tape_button.dart';
import '../ui/design/fidelity/fidelity_tier.dart';
import '../ui/design/fidelity/tier_detector.dart';
import '../ui/design/icons/icons.dart';
import '../ui/design/motion/motion_scope.dart';
import '../ui/design/render/render_kit.dart';
import '../ui/design/theme/tape_theme.dart';
import '../ui/design/tokens/colors.dart';
import '../ui/design/tokens/livery.dart';
import '../ui/design/tokens/spacing.dart';
import '../ui/dev/dev_settings.dart';
import '../ui/lab/design_lab.dart';
import '../ui/onboarding/onboarding_screen.dart';
import 'demo_drive.dart';
import 'drive_shell.dart';

/// Root widget.
///
/// The app opens on the cold open and the choice (DESIGN.md 7.11); the demo path
/// goes to the Strip, driven by Demo Mode (the connect path needs phase 6), with
/// one way into the design system: a small dev button that opens the Design Lab (DESIGN.md 13.2), shown
/// in debug and profile builds, and in a release build made with
/// `--dart-define=TAPEDASH_DEV=true`. It uses [WidgetsApp] rather than
/// `MaterialApp`, since Material widgets are banned (DESIGN.md 13.1).
class TapeDashApp extends StatelessWidget {
  const TapeDashApp({
    super.key,
    this.clock = const SystemClock(),
    this.scheduler = const SystemScheduler(),
    this.onboarding = true,
    this.skipColdOpen = DevMode.skipColdOpen,
  });

  /// Whether the app opens on the cold open and the choice (DESIGN.md 7.11), or
  /// straight on the drive (tests, and a later launch once the choice is
  /// remembered -- which needs the settings store, the Garage's piece).
  final bool onboarding;

  /// Goes straight to the choice, past the cold open.
  final bool skipColdOpen;

  /// Time, injected (CLAUDE.md 5): a test gives a `FakeClock` for both.
  final Clock clock;
  final Scheduler scheduler;

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: TapeColors.voidColor,
      debugShowCheckedModeBanner: false,
      builder: (context, child) => _Shell(
        clock: clock,
        scheduler: scheduler,
        onboarding: onboarding,
        skipColdOpen: skipColdOpen,
      ),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell({
    required this.clock,
    required this.scheduler,
    required this.onboarding,
    required this.skipColdOpen,
  });

  final Clock clock;
  final Scheduler scheduler;
  final bool onboarding;
  final bool skipColdOpen;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  late final TapeRenderKit _kit = TapeRenderKit();
  bool _labOpen = false;
  late bool _onboarded = !widget.onboarding;

  /// The fidelity tier the cold open's frame timings chose (DESIGN.md 9.2).
  FidelityTier _tier = FidelityTier.balanced;

  void _onBenchmark(List<double> frames) {
    final decision = const TierDetector().decide(frameMilliseconds: frames);
    if (decision.tier != _tier && mounted) {
      setState(() => _tier = decision.tier);
    }
  }

  /// The demo drive, started at launch so that it is already connected when
  /// the user chooses it (DESIGN.md 7.11: the ignition within a second). Not
  /// started when onboarding is off: the drive shell then starts its own.
  DemoDrive? _demo;

  @override
  void initState() {
    super.initState();
    if (widget.onboarding) {
      _demo = DemoDrive(clock: widget.clock, scheduler: widget.scheduler)
        ..start();
    }
    if (DevMode.launchScreen == 'lab') _labOpen = true;
  }

  @override
  void dispose() {
    _demo?.dispose();
    _kit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MotionScope(
      child: TapeRenderScope(
        kit: _kit,
        child: TapeTheme(
          data: TapeThemeData(livery: Liveries.ion, tier: _tier),
          child: _labOpen
              ? DesignLab(onClose: () => setState(() => _labOpen = false))
              : ColoredBox(
                  color: TapeColors.voidColor,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _onboarded
                            ? DriveShell(
                                demo: _demo,
                                clock: widget.clock,
                                scheduler: widget.scheduler,
                              )
                            : LayoutBuilder(
                                builder: (context, box) => TapeBackdrop(
                                  child: OnboardingScreen(
                                    width: box.maxWidth,
                                    height: box.maxHeight,
                                    skipColdOpen: widget.skipColdOpen,
                                    onBenchmark: _onBenchmark,
                                    onDemo: () =>
                                        setState(() => _onboarded = true),
                                  ),
                                ),
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
