/// The vertical tape's geometry (DESIGN.md 6.3) -- the aircraft-style speed
/// and RPM instrument the product is named for.
abstract final class TapeVerticalTape {
  /// The strip's width, as a share of a reference width W.
  static const double widthShareOfW = 0.13;

  /// The tape's readout box, a chamfered box straddling the inner edge.
  static const double readoutChamfer = 4;
  static const double readoutPaddingH = 6;
  static const double readoutPaddingV = 3;

  /// Tick lengths, as a share of the strip's own width.
  static const double minorTickShare = 0.35;
  static const double majorTickShare = 0.6;

  /// The top and bottom share of the tape that fades to void (DESIGN.md
  /// 6.3): full strength at this share in from an edge, nothing at the edge
  /// itself.
  static const double fadeShare = 0.2;

  /// The trend vector looks this many seconds ahead, at the value's current
  /// rate of change (DESIGN.md 6.3).
  static const double trendLookaheadSeconds = 5;
}
