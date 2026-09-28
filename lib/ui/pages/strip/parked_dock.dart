import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../vehicle/vehicle_state.dart' show DrivingMode;
import '../../design/components/controls/tape_button.dart';
import '../../design/icons/icons.dart';
import '../../design/motion/motion_clock.dart';
import '../../design/motion/spring_value.dart';
import '../../design/theme/palette.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/motion_tokens.dart';
import '../../design/tokens/shapes.dart';
import '../../design/tokens/spacing.dart';

/// The parked dock (DESIGN.md 7.1): in Parked mode a dock rises into the
/// floor zone with Garage, Pit Stop, Diagnostics and HUD -- chamfer buttons,
/// glyph plus label. The destinations do not exist yet (their real screens
/// are phase 4/5), so the buttons arrive disabled and carry the truth of
/// their own absence: a dock of buttons that say what is coming beats a
/// dock of dead taps.
///
/// The dock rises on `spring.reveal`, the buttons staggered by
/// [TapeMotion.stagger] (DESIGN.md 5.7), and falls on `spring.snap` inside
/// the 300 ms the motion return allows -- motion beats beauty (DESIGN.md
/// 7.2's "motion mode always wins"), so the fall cancels the rise in
/// flight rather than racing it.
///
/// The eco bar hides while parked (DESIGN.md 7.1); the eco bar does not
/// exist yet (phase 4), so there is nothing to hide.
class ParkedDock extends StatefulWidget {
  const ParkedDock({
    super.key,
    required this.mode,
    required this.motion,
    required this.width,
    required this.height,
  });

  /// Parked or motion (DESIGN.md 7.2), from the vehicle state.
  final ValueListenable<DrivingMode> mode;

  /// The clock the dock's own motion runs on.
  final MotionClock motion;

  final double width;
  final double height;

  @override
  State<ParkedDock> createState() => ParkedDockState();
}

class ParkedDockState extends State<ParkedDock> {
  late SpringValue _rise;

  @override
  void initState() {
    super.initState();
    _rise = SpringValue(
      clock: widget.motion,
      spec: TapeSprings.snap,
      initial: 0,
    )..addListener(_onRise);
    widget.mode.addListener(_onMode);
    _onMode();
  }

  @override
  void didUpdateWidget(ParkedDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.mode, widget.mode)) {
      oldWidget.mode.removeListener(_onMode);
      widget.mode.addListener(_onMode);
      _onMode();
    }
    if (!identical(oldWidget.motion, widget.motion)) {
      final at = _rise.value;
      _rise.dispose();
      _rise = SpringValue(
        clock: widget.motion,
        spec: TapeSprings.snap,
        initial: at,
      )..addListener(_onRise);
    }
  }

  @override
  void dispose() {
    _rise.removeListener(_onRise);
    _rise.dispose();
    super.dispose();
  }

  /// How far the dock has risen, 0 to 1.
  double get rise => _rise.value;

  void _onRise() {}

  void _onMode() {
    if (widget.mode.value == DrivingMode.parked) {
      // The rise: the dock's own spring, and the buttons staggered after it.
      _rise.setSpec(TapeSprings.reveal);
      _rise.retarget(1);
    } else {
      // The fall: inside the motion return's own 300 ms, cancelling
      // whatever rise is in flight.
      _rise.setSpec(TapeSprings.snap);
      _rise.retarget(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = TapeTheme.of(context);
    final palette = theme.palette;
    final rise = _rise.value;

    final buttons = <(TapeIcon, String)>[
      (TapeIcon.garage, 'Garage'),
      (TapeIcon.pitStop, 'Pit Stop'),
      (TapeIcon.checkEngine, 'Diagnostics'),
      (TapeIcon.hud, 'HUD'),
    ];

    final riseHeight = TapeShape.buttonHeight + TapeSpace.s1;
    // The dock's own floor: the tape's own 8 lp plus its own gap, so the
    // dock rises INTO the floor zone rather than under its own tape.
    final floor = TapeSpace.pageTapeHeight + TapeSpace.s1;
    final dockBottom = floor + riseHeight * (rise - 1);

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        children: [
          Positioned(
            bottom: dockBottom,
            left: 0,
            right: 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < buttons.length; i++) ...[
                  if (i > 0) const SizedBox(width: TapeSpace.s3),
                  _StaggeredDockButton(
                    index: i,
                    rise: _rise,
                    icon: buttons[i].$1,
                    label: buttons[i].$2,
                    palette: palette,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One dock button, staggered after the dock's own rise: the button fades
/// and rises in over [TapeMotion.stagger] after its own index, and falls
/// with the dock.
class _StaggeredDockButton extends StatelessWidget {
  const _StaggeredDockButton({
    required this.index,
    required this.rise,
    required this.icon,
    required this.label,
    required this.palette,
  });

  final int index;
  final ValueListenable<double> rise;
  final TapeIcon icon;
  final String label;
  final TapePalette palette;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: rise,
      builder: (context, _) {
        final own = _ownRise(index, rise.value);
        return Opacity(
          opacity: own.clamp(0.0, 1.0),
          child: TapeButton(label: label, icon: icon),
        );
      },
    );
  }

  /// The button's own rise: the dock's own rise, with the button's own
  /// stagger starting [TapeMotion.stagger] after its own index.
  static double _ownRise(int index, double rise) {
    // The stagger: one share of the dock's own rise per button, in the
    // dock's own six-item budget (DESIGN.md 5.7), so four buttons stagger
    // at 0, 1/6, 2/6 and 3/6 of the rise.
    final start = index / 6.0;
    return ((rise - start) / (1 - start)).clamp(0.0, 1.0);
  }
}
