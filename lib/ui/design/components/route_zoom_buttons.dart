import 'package:flutter/widgets.dart';

import '../icons/icons.dart';
import 'controls/tape_square_button.dart';
import 'route_view.dart';

/// Zoom in, zoom out and fit, for the route panel (DESIGN.md 6.12): three small
/// chamfered buttons for someone who would rather tap than pinch. Each is dimmed
/// when it can do nothing (in at the furthest, out and fit at the whole route).
///
/// In a replay two more come first: FOLLOW, which puts the camera back on the car
/// (lit while it is there), and, while it is, the map's turn: an arrow up when the
/// map turns with the car (heading up), an N when it stays north up. Zoom in and
/// out then bring the camera closer or further from the car, and fit lets go of it.
class RouteZoomButtons extends StatelessWidget {
  const RouteZoomButtons({
    super.key,
    required this.view,
    this.onFollow,
    this.headingUp = true,
    this.onHeading,
  });

  final RouteViewController view;

  /// Shown only in a replay (when given).
  final VoidCallback? onFollow;
  final VoidCallback? onHeading;

  /// Whether the map turns with the car while following.
  final bool headingUp;

  /// One button: a glyph in a chamfered frame, [size] lp square.
  static const double size = 36;

  @override
  Widget build(BuildContext context) {
    // It listens to the flags, which change when the buttons' states do, and not
    // to the view, which moves on every frame of a replay.
    return ValueListenableBuilder<int>(
      valueListenable: view.flags,
      builder: (context, flags, _) {
        final chasing = flags & 4 != 0;
        final zoomed = flags & 1 != 0 || chasing;
        final canIn = chasing ? flags & 8 == 0 : flags & 2 == 0;
        final canOut = chasing ? flags & 16 == 0 : zoomed;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onFollow != null) ...[
              if (chasing && onHeading != null) ...[
                TapeSquareButton(
                  icon: headingUp ? TapeIcon.heading : TapeIcon.north,
                  enabled: true,
                  onTap: onHeading!,
                ),
                const SizedBox(width: 4),
              ],
              TapeSquareButton(
                icon: TapeIcon.gps,
                enabled: true,
                lit: chasing,
                onTap: onFollow!,
              ),
              const SizedBox(width: 4),
            ],
            TapeSquareButton(
              icon: TapeIcon.zoomOut,
              enabled: canOut,
              onTap: view.zoomOut,
            ),
            const SizedBox(width: 4),
            TapeSquareButton(
              icon: TapeIcon.zoomIn,
              enabled: canIn,
              onTap: view.zoomIn,
            ),
            const SizedBox(width: 4),
            TapeSquareButton(
              icon: TapeIcon.fit,
              enabled: zoomed,
              onTap: view.reset,
            ),
          ],
        );
      },
    );
  }
}
