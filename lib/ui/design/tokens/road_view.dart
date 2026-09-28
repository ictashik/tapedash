/// The road view's geometry and motion (DESIGN.md 6.11).
abstract final class TapeRoadView {
  /// The horizon line's height, as a share of the view's own height.
  static const double horizonShare = 0.38;

  /// The two edge lines' half-width at the horizon and at the bottom, as a
  /// share of the view's width -- the convergence that gives the road its
  /// perspective.
  static const double roadHalfWidthAtHorizon = 0.06;
  // Leaves margin beyond the road's own edge at the bottom of the frame --
  // at 0.62 the edge line landed almost at the viewport's own edge, leaving
  // the speed streaks (drawn just outside it) nowhere on-screen to be for
  // most of their travel.
  static const double roadHalfWidthAtBottom = 0.46;

  /// Centre dashes: on/off period and duty cycle, in metres travelled (not
  /// seconds -- DESIGN.md's "truthful motion").
  static const double dashPeriodMetres = 6;
  static const double dashOnShare = 0.5;

  /// The lane grid's horizontal rungs, evenly spaced by depth share.
  static const int laneGridRungs = 6;

  /// The car's width at its widest, as a share of the view's width, and its
  /// height as a share of that width.
  static const double carWidthShare = 0.34;
  static const double carHeightShareOfWidth = 0.62;

  /// How far below the horizon the car's own base sits, as a share of the
  /// height below the horizon.
  static const double carBaseShare = 0.94;

  /// Body tilt limits (DESIGN.md 6.11), reached at 1g longitudinal or
  /// lateral.
  static const double pitchMaxDegrees = 2;
  static const double rollMaxDegrees = 3;

  /// Deceleration beyond this brightens the tail lights (DESIGN.md 6.11).
  static const double brakeThreshold = 1.5;

  /// Streaks appear above this speed, growing in density with it up to the
  /// fidelity tier's own cap (TierProfile.maxStreaks).
  static const double streakThresholdKmh = 60;
  static const double streakFullDensityKmh = 140;
  static const double streakLengthShare = 0.09;
  static const double streakMinLength = 5;

  /// The RPM bar's thickness, as a share of the height, along the horizon.
  static const double rpmBarThicknessShare = 0.012;
}
