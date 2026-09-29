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

  /// The vertical position slider's reach, either way, as a share of the height.
  static const double positionReach = 0.25;

  /// The scale slider's range (DESIGN.md 8).
  static const double scaleMin = 0.6;
  static const double scaleMax = 1.4;
}
