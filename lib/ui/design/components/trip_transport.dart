import 'package:flutter/widgets.dart';

import '../icons/icons.dart';
import '../motion/trip_player.dart';
import '../tokens/motion_tokens.dart';
import '../tokens/spacing.dart';
import 'controls/tape_square_button.dart';

/// The replay's transport (DESIGN.md 6.12): PLAY or PAUSE, the speed (1×, 2×, 3×,
/// and round again) and STOP, which leaves the replay. Three 48 lp buttons, 8 lp
/// apart, left of the scrubber.
///
/// PLAY starts a replay if there is none: [onToggle] is the page's to decide. The
/// speed can be chosen before a replay starts; STOP is dimmed until one has.
class TripTransport extends StatelessWidget {
  const TripTransport({
    super.key,
    required this.player,
    required this.replaying,
    required this.onToggle,
    required this.onStop,
  });

  final TripPlayer player;

  /// Whether a replay is on (its instruments are up): STOP can leave it.
  final bool replaying;

  final VoidCallback onToggle;
  final VoidCallback onStop;

  static const double buttonSize = TapeSpace.touchTarget;

  /// Three buttons and the two gaps between them.
  static const double width = buttonSize * 3 + TapeSpace.touchGap * 2;

  /// A rate as it is written on the button: "1×", "2×", "3×".
  static String rateLabel(double rate) => '${rate.round()}×';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: player.state,
      builder: (context, state, _) {
        final playing = state & 1 != 0;
        final rate = TapeReplay.rates[state >> 1];
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TapeSquareButton(
              icon: playing ? TapeIcon.pause : TapeIcon.play,
              size: buttonSize,
              lit: playing,
              onTap: onToggle,
            ),
            const SizedBox(width: TapeSpace.touchGap),
            TapeSquareButton(
              label: rateLabel(rate),
              size: buttonSize,
              onTap: player.cycleRate,
            ),
            const SizedBox(width: TapeSpace.touchGap),
            TapeSquareButton(
              icon: TapeIcon.stop,
              size: buttonSize,
              enabled: replaying,
              onTap: onStop,
            ),
          ],
        );
      },
    );
  }
}
