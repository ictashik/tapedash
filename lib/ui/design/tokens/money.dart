/// The money readout and the Money Tape (DESIGN.md 6.8).
abstract final class TapeMoney {
  /// The rupee glyph's size, as a share of the digit height.
  static const double rupeeShareOfDigitHeight = 0.55;

  /// Three small chamfered cells beside the value (DESIGN.md 6.8's
  /// confidence pips).
  static const int confidencePipCount = 3;
  static const double confidencePipSize = 6;
  static const double confidencePipGap = 3;
  static const double confidencePipChamfer = 1.5;

  /// A block is ₹1: this tall (the strip's own axis) with this gap between
  /// blocks, in logical pixels.
  static const double blockLength = 6;
  static const double blockGap = 2;

  /// The strip's own thickness, as a share of a reference width W (a
  /// vertical strip on the Money page; DESIGN.md 6.8 also allows a thin
  /// horizontal variant in the Drive floor, the same thickness share of its
  /// own reference).
  static const double thicknessShareOfW = 0.06;

  /// The newest block's phosphor flash (DESIGN.md 5.5's rise and decay,
  /// reused here rather than a second set of constants for the same curve).
  static const double flashPeakAlpha = 1.0;

  /// Blocks compacting into 5s and then 10s (DESIGN.md 6.8) is not yet
  /// built -- see the component's own doc comment. The strip currently
  /// just keeps growing; a real trip's length this would take to fill is
  /// Money-page-composition work, not this component's.
}
