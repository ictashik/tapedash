/// Alerts (DESIGN.md 6.10): the slot glyph, the critical bracket's pulse, and
/// the hysteresis that keeps a borderline reading from flickering.
abstract final class TapeAlerts {
  /// The alert-slot glyph's size: small for caution, large for critical.
  static const double slotGlyphSizeCaution = 28;
  static const double slotGlyphSizeCritical = 44;

  /// The critical bracket's pulse (DESIGN.md 6.10's "pulses at 1 Hz") -- a
  /// smooth breathing like the status strip's search pulse, not a hard
  /// flash like the shift horizon's redline (TapeMotion.pulseShare vs a
  /// flash's on/off step).
  static const double criticalPulseHz = 1;
  static const double criticalPulseAlphaMin = 0.5;
  static const double criticalPulseAlphaMax = 1.0;
  static const double criticalBracketArm = 14;

  /// The caution horizon line's thickness.
  static const double horizonLineThickness = 2;

  /// DESIGN.md 6.10 says alerts need "hysteresis and minimum durations so
  /// they never flicker" without giving exact numbers; these are this
  /// project's defaults (AlertHysteresis's constructor can override them).
  /// Quick to warn, slower to relax -- so a value bouncing right at its
  /// threshold settles on the safer (alerted) reading, not stuck flickering.
  static const Duration raiseAfter = Duration(seconds: 2);
  static const Duration fallAfter = Duration(seconds: 5);
}
