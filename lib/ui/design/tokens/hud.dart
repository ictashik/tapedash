/// The HUD's own rules (DESIGN.md 8): windshield optics ask for bold, simple
/// shapes and nothing else, so these numbers differ from the cluster's.
abstract final class TapeHud {
  /// Numerals are SemiBold or heavier (DESIGN.md 8); Bold is the `wght` used.
  static const double numeralWeight = 700;

  /// A label is at least 0.06H (DESIGN.md 8), against the cluster's 0.036H.
  static const double labelShare = 0.06;

  /// The huge single readout, as a share of the height: bigger than `hero`.
  static const double heroShare = 0.55;

  /// Each half of the Drive + Money layout.
  static const double halfShare = 0.36;

  /// The ₹/km line under the Money HUD's centre value.
  static const double secondaryShare = 0.16;

  /// The thin RPM bar's thickness, as a share of the height, never under the
  /// windshield's 5 lp stroke floor (`TapeStroke.hud`).
  static const double rpmBarShare = 0.035;

  /// The RPM bar's width, as a share of the width.
  static const double rpmBarWidthShare = 0.7;

  /// The RPM bar's scale, and where its red zone begins.
  static const double rpmMax = 8000;
  static const double rpmRedline = 6500;

  /// The redline part of the bar stands this much taller than the rest, so the
  /// zone is not told by colour alone (DESIGN.md 11).
  static const double rpmRedlineRise = 1.6;

  // The navigation layout (DESIGN.md 8, docs/NAV.md): the speed on the left, and
  // Google Maps' next turn on the right, all as shares of the height.

  /// The speed, in the left half.
  static const double navSpeedShare = 0.34;

  /// The side of the turn arrow's square.
  static const double navArrowShare = 0.34;

  /// The distance to the turn.
  static const double navDistanceShare = 0.17;

  /// The instruction under the arrow, in Maps' words, up to three lines of it: over
  /// the 0.06H a label may not be under.
  static const double navInstructionShare = 0.068;
  static const int navInstructionLines = 3;

  /// Where the arrow's ink starts in its picture, as a share of its side: Maps
  /// leaves a margin, and the HUD takes it back so that the arrow and the words
  /// under it start on one edge.
  static const double navArrowInset = 0.08;

  /// The ETA, the time left and the distance left along the bottom.
  static const double navFigureShare = 0.10;

  /// The approach line's stroke (never under `TapeStroke.hud`), the junction's
  /// ring and the car's dot.
  static const double navLineShare = 0.022;
  static const double navNodeShare = 0.034;
  static const double navDotShare = 0.03;

  /// How far from the turn the car's dot starts to climb the approach line, in
  /// metres: the line is Maps' distance to the turn, and a turn further away than
  /// this leaves the dot at the foot.
  static const double navApproachMetres = 500;

  /// The vertical position slider's reach, either way, as a share of the height.
  static const double positionReach = 0.25;

  /// The scale slider's range (DESIGN.md 8).
  static const double scaleMin = 0.6;
  static const double scaleMax = 1.4;
}
