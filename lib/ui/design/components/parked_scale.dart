import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../motion/parked_share.dart';

/// The parked choreography's hero shrink (DESIGN.md 7.2): a child that scales
/// itself to [parkedScaleShare] of its own size as [share] goes 0 to 1, on
/// the share's own spring.
///
/// A transition transform, deliberately not a re-layout: the glyph atlas
/// (DESIGN.md 9.3) is per font size, and re-laying the numerals out at every
/// intermediate size of a transition would rebuild it a frame at a time. The
/// child paints at its own size and the transform scales its layer, so a
/// hero shrinks smoothly to its parked size and back, and never re-atlases.
class ParkedScale extends StatelessWidget {
  const ParkedScale({
    super.key,
    required this.share,
    required this.parkedScaleShare,
    this.staggerIndex = 0,
    required this.child,
  });

  /// The parked share to follow, 0 in Motion and 1 parked.
  final ValueListenable<double> share;

  /// The share of its own size the child is when fully parked: the parked
  /// size divided by the size the child is built at, for instance
  /// `primary / hero` for a hero readout (DESIGN.md 7.2).
  final double parkedScaleShare;

  /// The item's place in the choreography's staggered group, so each piece
  /// starts [TapeMotion.stagger] after the one before it (DESIGN.md 5.7).
  final int staggerIndex;

  final Widget child;

  /// The scale the child is at for [staggerIndex], from the group's whole
  /// [parkedShare] (0 in Motion, 1 parked): `1` in Motion falling to
  /// [parkedScaleShare] parked, through the shared stagger. Exposed for a
  /// direct test, since sampling a scale back out of rendered pixels is the
  /// fragile way to check it.
  static double scaleFor({
    required double parkedShare,
    required double parkedScaleShare,
    int staggerIndex = 0,
  }) {
    final own = ParkedShare.staggered(
      parkedShare.clamp(0.0, 1.0),
      staggerIndex,
    );
    return 1.0 + (parkedScaleShare - 1.0) * own;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: share,
      child: child,
      builder: (context, child) {
        return Transform.scale(
          scale: scaleFor(
            parkedShare: share.value,
            parkedScaleShare: parkedScaleShare,
            staggerIndex: staggerIndex,
          ),
          child: child,
        );
      },
    );
  }
}
