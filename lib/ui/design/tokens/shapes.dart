/// The sizes of the shape language (DESIGN.md 4.6): the chamfer is the signature,
/// and things are grouped by brackets rather than boxes.
abstract final class TapeShape {
  /// A button's asymmetric chamfer: top-left and bottom-right cut at 8 lp, the
  /// other corners square.
  static const double buttonChamfer = 8;

  /// A panel or readout box's chamfer.
  static const double panelChamfer = 6;

  /// The chamfer of a small cell: a PID matrix cell, a confidence pip, a toggle.
  static const double cellChamfer = 3;

  /// The arms of an L-shaped corner bracket are 10 to 14 lp long.
  static const double bracketArm = 12;

  /// A button is 56 lp tall, and a touch target at least 48 (DESIGN.md 6.14).
  static const double buttonHeight = 56;

  /// A toggle's track (DESIGN.md 6.14).
  static const double toggleWidth = 48;
  static const double toggleHeight = 26;

  /// The tach's segments fill this share of their angular slot (DESIGN.md 6.2).
  static const double segmentFill = 0.70;

  /// The seven-segment renderer (DESIGN.md 6.17): an 8 degree italic skew, and a
  /// gap of 10% of a segment's thickness between segments.
  static const double sevenSegmentSkewDegrees = 8;
  static const double sevenSegmentGap = 0.10;

  /// A seven-segment digit's width and stroke, as shares of its height.
  static const double sevenSegmentAspect = 0.62;
  static const double sevenSegmentThickness = 0.15;

  /// The space between two digits, as a share of the digit's height.
  static const double sevenSegmentSpacing = 0.34;
}
