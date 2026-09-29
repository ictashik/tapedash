import 'dart:math' as math;

/// Spacing on a 4 lp base, and the layout constants of DESIGN.md 4.7.
abstract final class TapeSpace {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s12 = 48;

  /// The size the design is authored at (16:9), and the two others it is
  /// checked at: 18:9 and 20:9.
  static const double designWidth = 640;
  static const double designHeight = 360;
  static const double designWidth18x9 = 720;
  static const double designWidth20x9 = 800;

  /// The outer margin for a screen [height] lp tall: `max(16, 0.045H)`.
  static double margin(double height) => math.max(16, 0.045 * height);

  /// The minimum size of a touch target, and the gap between two (DESIGN.md 6.14).
  static const double touchTarget = 48;
  static const double touchGap = 8;

  // The zones of a driving screen, as shares of the height (DESIGN.md 4.7).

  /// The top strip: the shift horizon and the status.
  static const double horizonShare = 0.10;

  /// The bottom strip: the eco bar and trip values, with the page tape in its
  /// bottom 8 lp.
  static const double floorShare = 0.16;

  /// Where a cluster that fills its centre zone (Telemetry's grid, Minimal's hero
  /// column) stops at the bottom, so that the parked dock (56 lp of button, 12 lp
  /// above the edge: 0.19H on a 360 lp screen) never sits on its content. A little
  /// more than [floorShare], and the same in Motion, so nothing moves with the mode.
  static const double clearOfDockShare = 0.20;

  /// Where such a cluster starts at the top, so that the status strip's Parked
  /// captions (they add a line under each glyph) never sit on its content.
  static const double clearOfCaptionsShare = 0.15;

  /// The page tape's height, inside the floor.
  static const double pageTapeHeight = 8;

  /// The centre zone's width: `min(0.5W, 1.25H)`.
  static double centreWidth(double width, double height) =>
      math.min(0.5 * width, 1.25 * height);
}
