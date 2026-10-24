import 'package:flutter/widgets.dart';

import '../../design/components/tape_label.dart';
import '../../design/components/watch/watch_face.dart';
import '../../design/components/watch/watch_wheel.dart';
import '../../design/icons/icons.dart';
import '../../design/motion/motion_clock.dart';
import '../../design/theme/tape_theme.dart';
import '../../design/tokens/typography.dart';

/// The last face of the parked reel (DESIGN.md 16.5): it says MENU and opens the
/// wheel of the watch's own settings on a tap. (The wheel is not a face itself: it
/// would take the swipe and the bezel from the reel, and there would be no way
/// back to the speed.)
class WatchMenuCover extends StatelessWidget {
  const WatchMenuCover({super.key, required this.face});

  final WatchFace face;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final type = face.type;
    return SizedBox.square(
      dimension: face.diameter,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: face.heroY - type.primary * 1.3,
            child: Center(
              child: TapeIconView(
                TapeIcon.garage,
                size: type.primary * 1.3,
                color: palette.accentCore,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: face.heroY + type.primary * 0.4,
            child: Center(
              child: Text(
                'MENU',
                style: TapeType.wordmark(
                  size: type.primary,
                  color: palette.accentCore,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: face.heroY + type.primary * 1.6,
            child: Center(child: TapeLabel('tap to open', size: type.label)),
          ),
        ],
      ),
    );
  }
}

/// A screen over the reel (DESIGN.md 16.7): opaque `void` over the whole face, shut
/// by a swipe to the right (as a Wear user expects) or the Back button.
class WatchSheet extends StatelessWidget {
  const WatchSheet({
    super.key,
    required this.face,
    required this.onClose,
    required this.child,
  });

  final WatchFace face;
  final VoidCallback onClose;
  final Widget child;

  /// A swipe to the right faster than this closes the sheet, in lp a second.
  static const double closeVelocity = 300;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        if (details.velocity.pixelsPerSecond.dx > closeVelocity) onClose();
      },
      child: ColoredBox(
        color: palette.canvas,
        child: SizedBox.square(dimension: face.diameter, child: child),
      ),
    );
  }
}

/// A few plain words on the face, wrapped to the circle (DESIGN.md 16.1): what an
/// import or an export did. A tap, a swipe to the right or Back closes it.
class WatchMessage extends StatelessWidget {
  const WatchMessage({
    super.key,
    required this.face,
    required this.text,
    required this.onClose,
    this.ok = true,
    this.lines = const [],
  });

  final WatchFace face;
  final String text;
  final bool ok;

  /// Short lines under the sentence (what a setup would change).
  final List<String> lines;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = TapeTheme.of(context).palette;
    final type = face.type;
    final width = face.roomAt(face.radius, face.diameter * 0.55);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: SizedBox.square(
        dimension: face.diameter,
        child: Center(
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  textAlign: TextAlign.center,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TapeType.parkedSmall(
                    color: ok ? palette.inkBright : palette.caution,
                  ),
                ),
                for (final line in lines)
                  Text(
                    line,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TapeType.label(
                      size: type.label,
                      color: palette.inkMid,
                    ),
                  ),
                SizedBox(height: type.label),
                Text(
                  'TAP TO CLOSE',
                  style: TapeType.label(size: type.label, color: palette.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A wheel of choices where the one in force is lit (DESIGN.md 16.7): the source,
/// the livery. Choosing one sets it and closes.
class WatchChoiceWheel extends StatelessWidget {
  const WatchChoiceWheel({
    super.key,
    required this.title,
    required this.labels,
    required this.chosen,
    required this.face,
    required this.motion,
    required this.onChoose,
    this.rotary,
  });

  final String title;
  final List<String> labels;
  final int chosen;
  final WatchFace face;
  final MotionClock motion;
  final ValueChanged<int> onChoose;
  final Stream<int>? rotary;

  @override
  Widget build(BuildContext context) => WatchWheel(
    title: title,
    itemCount: labels.length,
    initial: chosen,
    face: face,
    motion: motion,
    rotary: rotary,
    rowAt: (i) => WheelRow(label: labels[i], lit: i == chosen),
    onChoose: onChoose,
  );
}
